// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get settingScopeHint =>
      'Borra un valor para usar el del nivel anterior. Los ajustes marcados ↻ se aplican al cargar el modelo.';

  @override
  String get settingExplicit => 'Personalizado';

  @override
  String get settingInherited => 'Heredado';

  @override
  String get settingOnePerLine => 'Uno por línea';

  @override
  String get nearbyHosts => 'Buscar anfitriones cercanos';

  @override
  String get nearbyHostsHint =>
      'Busca anfitriones OnDevice LLM en la misma red. Selecciona uno e introduce su clave de acceso o usa su código QR.';

  @override
  String get nearbyHostsNone =>
      'No se encontraron anfitriones. Activa el alojamiento en el otro dispositivo y comprueba que ambos usan la misma red. El emparejamiento manual sigue disponible.';

  @override
  String get scanConfidence => 'Confianza del reconocedor';

  @override
  String get scanSettings => 'Reconocimiento de texto';

  @override
  String get scanPageLimit => 'Páginas escaneadas por PDF';

  @override
  String get scanLongHint =>
      'El texto integrado se lee después de este límite. Los escaneos largos muestran el progreso y se pueden detener.';

  @override
  String get scanLanguage => 'Idioma de reconocimiento';

  @override
  String get scanLatinHint =>
      'Android reconoce automáticamente inglés, francés, español y otros textos de alfabeto latino en este dispositivo.';

  @override
  String get scanQualityHint =>
      'La confianza del reconocedor puede ser errónea. Comprueba el texto importante con el original.';

  @override
  String get modelSettingsAll => 'Todos los ajustes del modelo';

  @override
  String get modelSettingsGlobal => 'Tus ajustes del modelo';

  @override
  String get modelSettingsAllHint =>
      'Editar o restablecer los ajustes de perfiles, preajustes y conversaciones';

  @override
  String get removeProjectHint =>
      '¿Eliminar este proyecto y sus instrucciones? Se conservarán sus conversaciones y archivos.';

  @override
  String get downloadQueued => 'Esperando un turno de descarga';

  @override
  String get sourceMessage => 'Mensaje de origen';

  @override
  String get sourceMessageMissing =>
      'Este mensaje de origen ya no está disponible.';

  @override
  String get openConversation => 'Abrir conversación';

  @override
  String get contextSummary => 'Revisar resumen del contexto';

  @override
  String get contextSummaryHint =>
      'Escribe un resumen de estos mensajes anteriores. Revísalo antes de guardarlo; las respuestas posteriores podrán usarlo en lugar de esta parte de la conversación.';

  @override
  String get contextSummaryTooShort =>
      'Se necesita más historial para crear un resumen.';

  @override
  String get memoryUsed => 'Memoria utilizada';

  @override
  String get unverifiedFeatures => 'Características que requieren verificación';

  @override
  String get restoreVersion => 'Usar esta versión';

  @override
  String get originalFile => 'Compartir archivo original';

  @override
  String get previousVersion => 'Versión anterior';

  @override
  String get workspaceTitle => 'Proyectos y conversaciones';

  @override
  String get project => 'Proyecto';

  @override
  String get projectName => 'Nombre del proyecto';

  @override
  String get projectInstructions => 'Instrucciones para este proyecto';

  @override
  String get noProject => 'Sin proyecto';

  @override
  String get archivedChats => 'Archivadas';

  @override
  String get trashChats => 'Papelera';

  @override
  String get archiveChats => 'Archivar';

  @override
  String get restoreChats => 'Restaurar';

  @override
  String get moveToTrash => 'Mover a la papelera';

  @override
  String get permanentDeleteHint =>
      'Eliminar permanentemente estas conversaciones y archivos adjuntos del dispositivo. No se puede deshacer.';

  @override
  String get selectAllChats => 'Seleccionar todo';

  @override
  String get temporaryChat => 'Chat temporal';

  @override
  String get temporaryChatHint =>
      'Este chat y su borrador permanecen en memoria. La memoria personal está desactivada. Se descartan al salir; las solicitudes remotas y web siguen usando la conexión seleccionada.';

  @override
  String get deleteAnswer => 'Eliminar respuesta';

  @override
  String get deleteQuestionAnswer => 'Eliminar pregunta y respuesta';

  @override
  String get messageDeleted => 'Mensaje eliminado';

  @override
  String get undo => 'Deshacer';

  @override
  String get undoUnavailable =>
      'No se puede deshacer mientras se ejecuta otra operación.';

  @override
  String get appTitle => 'OnDevice';

  @override
  String get noModelLoaded => 'ningún modelo cargado';

  @override
  String get newChat => 'Nuevo chat';

  @override
  String get drawerTemporary => 'Temporal';

  @override
  String get drawerWorkspace => 'Espacio de trabajo';

  @override
  String get drawerProjects => 'Proyectos y conversaciones';

  @override
  String get drawerProjectsHint => 'Proyectos, archivo y papelera';

  @override
  String drawerProjectsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count proyectos',
      one: '1 proyecto',
      zero: 'Agrupa chats con instrucciones comunes',
    );
    return '$_temp0';
  }

  @override
  String get previous7Days => 'Últimos 7 días';

  @override
  String get previous30Days => 'Últimos 30 días';

  @override
  String get olderChats => 'Más antiguos';

  @override
  String get chatOptions => 'Opciones del chat';

  @override
  String get shareOrExport => 'Compartir o exportar';

  @override
  String get thisChatSection => 'Este chat';

  @override
  String get conversations => 'Conversaciones';

  @override
  String get more => 'Más';

  @override
  String get exportMarkdown => 'Exportar Markdown';

  @override
  String get exportJson => 'Exportar JSON';

  @override
  String get shareAsText => 'Compartir como texto';

  @override
  String get createDocument => 'Crear documento';

  @override
  String get documentFormat => 'Formato';

  @override
  String get answersOnly => 'Solo respuestas del asistente';

  @override
  String get includeBranches => 'Incluir ramas anteriores';

  @override
  String get includeReasoning => 'Incluir razonamiento del modelo';

  @override
  String get saveDocument => 'Guardar documento';

  @override
  String get models => 'Modelos';

  @override
  String get settings => 'Configuración';

  @override
  String get metrics => 'Métricas';

  @override
  String get loadingModel => 'Cargando modelo en la memoria...';

  @override
  String get messageHint => 'Envía un mensaje a tu modelo...';

  @override
  String get listening => 'Escuchando…';

  @override
  String get chooseModel => 'Elige un modelo';

  @override
  String get think => 'Pensar';

  @override
  String get thinkOff => 'Desactivado';

  @override
  String get thinkLow => 'Bajo';

  @override
  String get thinkMedium => 'Medio';

  @override
  String get thinkHigh => 'Alto';

  @override
  String get thinkOffHint => 'Responde enseguida. Lo más rápido.';

  @override
  String get thinkLowHint => 'Un razonamiento breve primero (unos 500 tokens).';

  @override
  String get thinkMediumHint =>
      'Razona más tiempo primero (unos 2000 tokens), para preguntas difíciles.';

  @override
  String get thinkHighHint =>
      'Razona a fondo primero (unos 8000 tokens). Lo más lento.';

  @override
  String thinkLevelToast(String level) {
    return 'Pensamiento: $level';
  }

  @override
  String get thinkOffToast => 'Pensamiento desactivado';

  @override
  String get attachTooltip =>
      'Adjuntar una foto o archivo, o elegir herramientas';

  @override
  String get dictate => 'Dictar';

  @override
  String get stopDictation => 'Detener dictado';

  @override
  String get send => 'Enviar mensaje';

  @override
  String get stop => 'Detener generación';

  @override
  String get modelPill => 'Modelo';

  @override
  String get webLocal => 'Local';

  @override
  String get webAuto => 'automático';

  @override
  String get webAlways => 'siempre';

  @override
  String get emptyTitle =>
      'Un poco más de inteligencia.\nMucha más privacidad.';

  @override
  String get emptyHasModel =>
      'Tu modelo se ejecuta por completo en este dispositivo. Pregúntale lo que quieras.';

  @override
  String emptyRemote(String host) {
    return 'Las respuestas vienen de tu servidor remoto ($host); tus mensajes se envían allí. Pregúntale lo que quieras.';
  }

  @override
  String get emptyNoModel =>
      'Aún no hay ningún modelo. Abre Modelos para descargar uno inicial o importar tu propio GGUF; luego vuelve y pregunta lo que quieras.';

  @override
  String get askPhoto => 'Pregunta por una foto';

  @override
  String get askFile => 'Preguntar por un archivo';

  @override
  String get generating => 'generando…';

  @override
  String get runDetails => 'Cómo se generó esta respuesta';

  @override
  String get answerWarning => 'Lo que la verificación de fuentes pone en duda';

  @override
  String get copyRunDetails => 'Copiar detalles de ejecución';

  @override
  String get runDetailsCopied => 'Detalles de la ejecución copiados';

  @override
  String get runMeasured => 'MEDIDO';

  @override
  String get runSettings => 'Configuraciones vigentes';

  @override
  String get runEngine => 'MOTOR';

  @override
  String get copyResponse => 'Copiar respuesta';

  @override
  String get copyQuestion => 'Copiar la pregunta';

  @override
  String get responseCopied => 'Respuesta copiada';

  @override
  String get readAloud => 'leer en voz alta';

  @override
  String get stopReading => 'dejar de leer';

  @override
  String get regenerate =>
      'Regenerar (mantiene esta respuesta como una versión anterior)';

  @override
  String get continueAnswer => 'continúa esta respuesta';

  @override
  String get compareWith => 'Comparar con otro modelo';

  @override
  String get editQuestion => 'Editar pregunta';

  @override
  String get askAgain => 'Preguntar de nuevo';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get earlierQuestion => 'Pregunta anterior';

  @override
  String get earlierAnswer => 'respuesta anterior';

  @override
  String get restoreBranch => 'Restaurar esta rama';

  @override
  String get stoppedPartial => 'Detenido · respuesta parcial';

  @override
  String get interruptedClosed =>
      'Interrumpido · la aplicación se cerró antes de que terminara la respuesta';

  @override
  String get interruptedPartial => 'Interrumpido · respuesta parcial';

  @override
  String get interruptedError => 'Interrumpido por un error';

  @override
  String get searchConversations => 'Buscar conversaciones';

  @override
  String get storedOnDevice => 'Almacenado solo en este dispositivo';

  @override
  String get noConversations =>
      'Aún no hay conversaciones.\nTus chats aparecerán aquí.';

  @override
  String nothingMatches(String query) {
    return 'Nada coincide con \"$query\".';
  }

  @override
  String get pinned => 'Fijado';

  @override
  String get today => 'hoy';

  @override
  String get yesterday => 'ayer';

  @override
  String get earlier => 'Antes';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Seguir el idioma del teléfono';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageSpanish => 'Español';

  @override
  String get resetToDefaults => 'Restablecer los valores predeterminados';

  @override
  String get sectionAssistant => 'Asistente';

  @override
  String get thinkingMode => 'Modo de pensamiento';

  @override
  String get thinkingModeHint =>
      'Muestre el razonamiento generado por el modelo cuando sea compatible. Puede contener errores y no es prueba de corrección.';

  @override
  String get webResearch => 'Investigación web (sin clave)';

  @override
  String get webOffHint => 'Nada sale del teléfono.';

  @override
  String get webAutoHint =>
      'La pregunta va a DuckDuckGo y las páginas de resultados se recuperan cuando el mensaje lo necesita.';

  @override
  String get webAlwaysHint =>
      'Cada mensaje se investiga primero. Más lento, siempre actual.';

  @override
  String get knowledgeLibrary => 'Biblioteca de conocimientos';

  @override
  String get knowledgeOff =>
      'Desactivado · tus documentos, citados en las respuestas cuando están activos';

  @override
  String knowledgeOn(Object collection) {
    return 'En · $collection';
  }

  @override
  String get memory => 'Memoria';

  @override
  String get memoryOnHint =>
      'Activado · el asistente aprende datos duraderos sobre usted a través de los chats';

  @override
  String get memoryOffHint => 'Apagado · no se recuerda nada entre chats';

  @override
  String get readAloudSetting => 'Leer las respuestas en voz alta';

  @override
  String get readAloudHint =>
      'Cada respuesta finalizada se pronuncia con la voz de texto a voz del teléfono. El ícono del altavoz en una respuesta la lee a pedido de cualquier manera.';

  @override
  String get dictationOnDevice => 'El dictado permanece en el teléfono';

  @override
  String get dictationOnDeviceHint =>
      'Utilice únicamente el reconocedor del dispositivo (necesita un paquete de idioma sin conexión en la configuración de voz del teléfono). Apagado permite el reconocedor de red.';

  @override
  String get customInstructions => 'Instrucciones personalizadas del sistema';

  @override
  String get customInstructionsHint => 'Añade preferencias para tu asistente';

  @override
  String get sectionModel => 'Modelo';

  @override
  String get remoteServer => 'Servidor remoto';

  @override
  String get sectionAdvanced => 'Avanzado';

  @override
  String get contextAndBatch => 'Contexto y lote';

  @override
  String get hardware => 'Hardware';

  @override
  String get sampling => 'Muestreo';

  @override
  String get reasoningAndSearch => 'Razonamiento y búsqueda';

  @override
  String get sectionAbout => 'Acerca de';

  @override
  String get openSourceMit => 'Código abierto · MIT';

  @override
  String get builtOnLlama => 'Construido en llama.cpp';

  @override
  String get builtOnLlamaHint => 'Motor de inferencia del proyecto ggml.';

  @override
  String get openSourceLicences => 'Licencias de código abierto';

  @override
  String get openSourceLicencesHint =>
      'Paquetes, modelos y voces, con sus licencias';

  @override
  String get resetQuestion => '¿Restablecer los valores predeterminados?';

  @override
  String get resetHint =>
      'Todos los asistentes, modelos y configuraciones avanzadas vuelven a los valores predeterminados para este dispositivo. Tus chats no se ven afectados.';

  @override
  String get reset => 'Reiniciar';

  @override
  String get enableWebQuestion => '¿Habilitar la búsqueda web?';

  @override
  String get enableWebHint =>
      'La pregunta se envía a DuckDuckGo y las páginas de resultados se obtienen directamente de sus sitios web (que pueden ver tu dirección IP). No se usa ninguna cuenta ni clave; las conversaciones, el modelo y la configuración permanecen en el dispositivo.';

  @override
  String get enable => 'Habilitar';

  @override
  String get systemInstructions => 'Instrucciones del sistema';

  @override
  String get systemInstructionsHint =>
      'por ej. Responde brevemente. Prefiere unidades métricas.';

  @override
  String get couldNotOpenLink => 'No se pudo abrir este enlace.';

  @override
  String get privateByDefault => 'Privado por defecto';

  @override
  String get privateByDefaultHint =>
      'Sin cuentas, análisis ni inferencias en la nube. Las descargas y la búsqueda opcional son las únicas funciones de la red.';

  @override
  String get noModelLoadedTitle => 'Ningún modelo cargado';

  @override
  String get chooseFromLibrary => 'Elige uno de la biblioteca';

  @override
  String get obPrivateHeadline => 'Privado por construcción';

  @override
  String get obPrivateBody =>
      'Un modelo de lenguaje que se ejecuta en el propio chip de tu teléfono. No hay ningún servidor en el otro extremo.';

  @override
  String get obNoAccount => 'Sin cuenta';

  @override
  String get obNoAccountHint =>
      'No hay nada para registrarse, nada para iniciar sesión.';

  @override
  String get obNoCloud => 'Sin nube';

  @override
  String get obNoCloudHint =>
      'Cada respuesta se calcula aquí. El modo avión funciona.';

  @override
  String get obStaysHere =>
      'Los modelos y los chats permanecen en este teléfono.';

  @override
  String get obStaysHereHint =>
      'Elimina la aplicación y cada byte desaparecerá con ella.';

  @override
  String get continueLabel => 'Continuar';

  @override
  String get obPickModel => 'Elige un modelo inicial';

  @override
  String get phoneRamUnknown => 'Este teléfono · RAM desconocida';

  @override
  String phoneRam(Object gb) {
    return 'Este teléfono · $gb GB RAM';
  }

  @override
  String get recommended => 'Recomendado';

  @override
  String get orChooseAnother => 'O elegir otro';

  @override
  String get acknowledgeLicense =>
      'Reconozco la licencia de modelo del editor.';

  @override
  String get download => 'Descargar';

  @override
  String get later => 'Más tarde';

  @override
  String get obReady => 'Listo.';

  @override
  String get startChatting => 'Empezar a chatear';

  @override
  String get downloadInterrupted => 'Descarga interrumpida';

  @override
  String get downloadInterruptedHint =>
      'Puede volver a intentarlo ahora u omitirlo y descargarlo más tarde desde la biblioteca de modelos. La aplicación funciona sin modelo, simplemente no puede responder todavía.';

  @override
  String get retry => 'Reintentar';

  @override
  String get skipForNow => 'Saltar por ahora';

  @override
  String get verifyingSha => 'Verificando SHA-256…';

  @override
  String pausedOf(Object received, Object size) {
    return 'En pausa · $received de $size';
  }

  @override
  String get starting => 'Empezando…';

  @override
  String get downloading => 'Descargando';

  @override
  String get downloadingHint =>
      'Mantenga la aplicación abierta. Puede pausar y reanudar; el archivo se compara con el SHA-256 del editor cuando finaliza.';

  @override
  String get resume => 'Reanudar';

  @override
  String get verifying => 'Verificando…';

  @override
  String get pause => 'Pausa';

  @override
  String get skip => 'Saltar';

  @override
  String get presets => 'Preajustes';

  @override
  String get newLabel => 'Nuevo';

  @override
  String get noExtraInstructions => 'Sin instrucciones adicionales';

  @override
  String get edit => 'Editar';

  @override
  String get duplicate => 'Duplicar';

  @override
  String get delete => 'Eliminar';

  @override
  String get presetsHint =>
      'Un ajuste preestablecido agrega sus instrucciones a las suyas y puede anular la temperatura, el pensamiento y el modo web. Las funciones integradas se pueden duplicar y editar.';

  @override
  String get newPreset => 'Nuevo preajuste';

  @override
  String get editPreset => 'Editar preajuste';

  @override
  String get name => 'Nombre';

  @override
  String get instructions => 'Instrucciones';

  @override
  String get instructionsHint => '¿Cómo debe comportarse el asistente?';

  @override
  String get temperature => 'Temperatura';

  @override
  String get useSetting => 'Usar configuración';

  @override
  String get thinking => 'Pensando';

  @override
  String get on => 'encendido';

  @override
  String get off => 'Apagado';

  @override
  String get webResearchShort => 'investigación web';

  @override
  String get unpin => 'Desanclar';

  @override
  String get pinToTop => 'Fijar arriba';

  @override
  String get rename => 'Cambiar nombre';

  @override
  String get moveToFolder => 'Mover a la carpeta';

  @override
  String get tags => 'Etiquetas';

  @override
  String get renameConversation => 'Cambiar el nombre de la conversación';

  @override
  String get tagsCommaSeparated => 'Etiquetas (separadas por comas)';

  @override
  String get newFolder => 'Nueva carpeta…';

  @override
  String get removeFromFolder => 'Quitar de la carpeta';

  @override
  String get folderName => 'Nombre de la carpeta';

  @override
  String get deleteConversationQuestion => '¿Eliminar conversación?';

  @override
  String get keep => 'mantener';

  @override
  String couldNotDelete(Object error) {
    return 'No se pudo eliminar: $error';
  }

  @override
  String get clear => 'Borrar';

  @override
  String get all => 'Todos';

  @override
  String get knowledgeIntro =>
      'Importe documentos una vez (PDF, Word, texto, código, EPUB...) y cada pregunta se responderá con los pasajes que mejor coincidan de la colección activa, citados como fuentes web. La recuperación se realiza íntegramente en el teléfono: clasificación del texto completo, más el significado una vez que se descarga el modelo de incrustación.';

  @override
  String get newCollection => 'Nueva colección';

  @override
  String get useInChats => 'Usar en chats';

  @override
  String get collectionOff =>
      'Desactivado: no se ha consultado ninguna colección';

  @override
  String collectionActive(Object collection) {
    return 'Activo: $collection';
  }

  @override
  String get readingAndIndexing => 'Lectura e indexación…';

  @override
  String get noCollections =>
      'Aún no hay colecciones. Crea una con el icono de carpeta y luego añade archivos.';

  @override
  String get addFiles => 'Agregar archivos';

  @override
  String get deleteCollection => 'Eliminar colección';

  @override
  String get searchByMeaning => 'Buscar por significado';

  @override
  String get ready => 'Listo';

  @override
  String indexForMeaning(Object count) {
    return 'Indexar $count pasajes para la búsqueda semántica';
  }

  @override
  String indexingProgress(Object done, Object total) {
    return 'Indexación por significado... $done/$total';
  }

  @override
  String downloadMb(Object mb) {
    return 'Descargar · ${mb}MB';
  }

  @override
  String get addMemory => 'Añadir un recuerdo';

  @override
  String get editMemory => 'Editar memoria';

  @override
  String get forgetEverything => 'olvida todo';

  @override
  String get forgetEverythingQuestion => '¿Olvidarlo todo?';

  @override
  String forgetEverythingHint(Object count) {
    return 'Se eliminarán todos los datos $count recordados. Los chats no se ven afectados.';
  }

  @override
  String get forget => 'olvidar';

  @override
  String get rememberAboutMe => 'Recuerda cosas sobre mi';

  @override
  String get rememberAboutMeHint =>
      'Recordar los hechos duraderos que compartes, como tu trabajo y preferencias. Las notas se guardan en este dispositivo. Compartirlas y extraerlas con un modelo remoto requiere permiso para esa conexión. Puedes editar o borrar las notas abajo.';

  @override
  String get memoryStorageHint =>
      'Las notas se guardan en este dispositivo. Cada conexión remota necesita permiso aparte para recibirlas o aprenderlas.';

  @override
  String get memoryRemoteLocalHint =>
      'Las afirmaciones claras, como tu trabajo o nombre, pueden guardarse localmente con Memoria activada. Activa compartir para que esta conexión use tus notas, y aprender para extraer otros hechos duraderos.';

  @override
  String get whatAssistantRemembers => 'Lo que recuerda el asistente';

  @override
  String get nothingYetFills => 'Nada todavía. Se completa mientras chateas.';

  @override
  String get nothingStoredSwitch =>
      'Nada almacenado. Encienda el interruptor o agregue datos a mano con +.';

  @override
  String get switchModel => 'Cambiar modelo';

  @override
  String get nothingOnPhone => 'Aún no hay nada en este teléfono.';

  @override
  String get modelsOnPhone =>
      'Modelos en este teléfono. El activo responde tus chats.';

  @override
  String get modelUnloaded =>
      'Modelo liberado de la memoria. Se volverá a cargar con tu próximo mensaje.';

  @override
  String get unloadModel => 'Liberar modelo de la memoria';

  @override
  String get openModelLibrary => 'Biblioteca de modelos abierta';

  @override
  String get active => 'Activo';

  @override
  String get pickerEmptyHint =>
      'Descargue un modelo de la biblioteca o importe un GGUF que ya posee. Los chats necesitan un modelo cargado; Todo queda en este teléfono.';

  @override
  String get takePhoto => 'Tomar una foto';

  @override
  String get attachCamera => 'Cámara';

  @override
  String get attachFile => 'Archivo';

  @override
  String get attachGoalShort => 'Objetivo';

  @override
  String get photos => 'Fotos';

  @override
  String get photosHint => 'JPEG, PNG, WebP, HEIC…';

  @override
  String get documentOrFile => 'Documento o archivo';

  @override
  String get documentHint =>
      'PDF, Word, PowerPoint, Excel, OpenDocument, EPUB, RTF, texto, código, CSV, JSON, HTML…';

  @override
  String couldNotOpenPicker(Object error) {
    return 'No se pudo abrir el selector: $error';
  }

  @override
  String get readingAttachments => 'Leyendo archivos adjuntos...';

  @override
  String get turnOnWebQuestion => '¿Activar la búsqueda web?';

  @override
  String get turnOnWebHint =>
      'Cuando pega un enlace, solicita realizar una búsqueda o una pregunta parece urgente, la pregunta se envía a DuckDuckGo y las páginas de resultados (tres de forma predeterminada, Configuración > Razonamiento y búsqueda) se obtienen directamente de sus sitios web (ven su dirección IP). Con la inferencia local, todo lo demás permanece en este dispositivo. Si el servidor remoto está habilitado, la pregunta y el contexto proporcionado también se envían a ese servidor.';

  @override
  String get stayLocal => 'Mantente local';

  @override
  String get turnOn => 'encender';

  @override
  String get compareWithTitle => 'Comparar con…';

  @override
  String get compareHint =>
      'La misma pregunta y evidencia, respondida por otro modelo. Se muestra al lado de esta respuesta; no forma parte de la conversación.';

  @override
  String shareFailed(Object error) {
    return 'Error al compartir: $error';
  }

  @override
  String exportFailed(Object error) {
    return 'Error al exportar: $error';
  }

  @override
  String get dismiss => 'Descartar';

  @override
  String licenseLabel(Object license) {
    return 'Licencia · $license';
  }

  @override
  String get resumeRetry => 'Reanudar/reintentar';

  @override
  String get useModel => 'Usar modelo';

  @override
  String get remove => 'Quitar';

  @override
  String get benchmark => 'Prueba de rendimiento';

  @override
  String visionPercent(Object percent) {
    return 'Visión $percent%';
  }

  @override
  String get verifyingVision => 'Verificando la visión...';

  @override
  String get visionReady => 'Visión lista';

  @override
  String addVisionMb(Object mb) {
    return 'Añadir visión · $mb MB';
  }

  @override
  String get addFromHf => 'Añadir desde Hugging Face';

  @override
  String get importGguf => 'Importar un GGUF';

  @override
  String get addFromHfHint =>
      'Pegue el enlace a un único archivo GGUF público. Su tamaño, suma de verificación y licencia se mostrarán antes de descargar.';

  @override
  String get importGgufHint =>
      'Elija un GGUF que haya descargado usted mismo. Se copiará en su biblioteca de modelos privada; deje suficiente espacio para una segunda copia.';

  @override
  String get ggufLink => 'Enlace al archivo GGUF';

  @override
  String get templateFallback => 'Plantilla alternativa';

  @override
  String get automaticMetadata => 'Automático (metadatos del modelo)';

  @override
  String get ggufWarning =>
      'Sólo modelos de generación de texto. Un GGUF puede requerir más RAM que su tamaño de descarga. Es posible que no se admitan nuevas arquitecturas ni archivos divididos.';

  @override
  String get checkModel => 'Consultar modelo';

  @override
  String get chooseFile => 'Elige el archivo';

  @override
  String get checkingMetadata => 'Comprobando los metadatos del modelo...';

  @override
  String downloadQuestion(Object model) {
    return 'Descargar $model?';
  }

  @override
  String get modelCard => 'Ficha del modelo';

  @override
  String get removeModelQuestion => '¿Quitar este modelo?';

  @override
  String removeModelHint(Object model, Object size) {
    return '¿Eliminar $model de esta aplicación y liberar $size? Tus chats se conservarán.';
  }

  @override
  String get browseHf => 'Explorar Hugging Face';

  @override
  String get yourModelLibrary => 'Tu biblioteca de modelos';

  @override
  String get libraryHint =>
      'Descargue un modelo inicial, agregue un enlace de archivo Hugging Face o importe un GGUF que ya posee. Después de la descarga, la inferencia funciona sin conexión.';

  @override
  String get searchHf => 'Buscar en Hugging Face';

  @override
  String get pasteLink => 'Pegar enlace';

  @override
  String get importGgufButton => 'Importar GGUF';

  @override
  String get checkingCopying => 'Comprobando y copiando modelo...';

  @override
  String get preparingLibrary => 'Preparando tu biblioteca…';

  @override
  String get onThisDevice => 'En este dispositivo';

  @override
  String get nothingDownloaded =>
      'Aún no se ha descargado nada. Elija un modelo a continuación para comenzar.';

  @override
  String get availableToDownload => 'Disponible para descargar';

  @override
  String get everythingOnPhone =>
      'Todo lo que hay en el catálogo está en este teléfono.';

  @override
  String get justNow => 'justo ahora';

  @override
  String minutesAgo(Object n) {
    return 'hace $n min';
  }

  @override
  String hoursAgo(Object n) {
    return 'hace $n h';
  }

  @override
  String get webModeOff => 'Apagado · permanece local';

  @override
  String get webModeAuto =>
      'Auto · enlaces, búsquedas y preguntas de actualidad';

  @override
  String get webModeAlways => 'Siempre · investiga cada mensaje';

  @override
  String rememberedOne(Object fact) {
    return 'Recordado: $fact';
  }

  @override
  String rememberedMore(Object fact, Object more) {
    return 'Recordado: $fact (+$more)';
  }

  @override
  String get reviewMemory => 'Repasar lo recordado';

  @override
  String get memoryDialogTitle => 'Memoria';

  @override
  String get memoryDialogHint =>
      'La memoria guarda los datos breves que dices sobre ti mismo para que los chats posteriores ya los conozcan. Se almacena únicamente en este teléfono y puede cambiarlo en cualquier momento en Configuración > Memoria. Esto es lo que se acaba de anotar: edítelo, consérvelo o deséchelo.';

  @override
  String get memoryDialogFieldHint =>
      'Un hecho por línea; las líneas vacías se eliminan';

  @override
  String get discard => 'Descartar';

  @override
  String get goalDescribeFirst => 'Describe el objetivo primero.';

  @override
  String get goalLimitsInvalid =>
      'Ingrese límites positivos de pasos, tiempo, tokens y herramientas.';

  @override
  String get goalsTitle => 'Objetivos';

  @override
  String get goalIntro =>
      'Dale al modelo una meta. Planifica las preguntas a investigar, busca cada una de ellas, compara los hallazgos con sus criterios, llena los vacíos y escribe un informe citado.';

  @override
  String get goalWebOff =>
      'La investigación web está desactivada, así que el objetivo solo puede usar lo que el modelo ya sabe. Actívala con el icono del globo en el campo de chat para obtener fuentes.';

  @override
  String get goalLabel => 'Objetivo';

  @override
  String get goalExample =>
      'Compara los tres coches eléctricos más populares en Canadá para una familia de cuatro';

  @override
  String get goalKindTitle => 'Tipo de investigación';

  @override
  String get goalCriteriaLabel =>
      'Qué debe incluir un buen resultado (opcional)';

  @override
  String get goalBudgetTitle => 'Cuánto trabajo';

  @override
  String get goalMaxSteps => 'Pasos máximos de investigación';

  @override
  String get goalMaxMinutes => 'Minutos máximos';

  @override
  String get goalMaxTokens => 'Presupuesto aproximado de tokens';

  @override
  String get goalMaxToolCalls => 'Llamadas máximas a herramientas';

  @override
  String get goalKeepOpen =>
      'Mantenga la aplicación abierta: Android puede detenerla en segundo plano. El progreso se guarda después de cada paso.';

  @override
  String get goalStart => 'Iniciar objetivo';

  @override
  String get goalBudgetQuick => 'Rápido';

  @override
  String get goalBudgetQuickHint =>
      'Aproximadamente 4 búsquedas · hasta 10 min';

  @override
  String get goalBudgetStandard => 'Estándar';

  @override
  String get goalBudgetStandardHint =>
      'Aproximadamente 8 búsquedas · hasta 30 min';

  @override
  String get goalBudgetDeep => 'Profundo';

  @override
  String get goalBudgetDeepHint =>
      'Aproximadamente 14 búsquedas · hasta 60 min';

  @override
  String get goalBudgetUnlimited => 'Ilimitado';

  @override
  String get goalBudgetUnlimitedHint =>
      'Hasta que termine, esté en pausa o se detenga';

  @override
  String get goalBudgetCustom => 'personalizado';

  @override
  String get goalBudgetCustomHint => 'Establece tus propios límites';

  @override
  String get goalPhasePlanning => 'Planificando la investigación';

  @override
  String get goalPhaseResearching => 'investigando';

  @override
  String get goalPhaseChecking => 'Comprobando los hallazgos con tus criterios';

  @override
  String get goalPhaseWriting => 'Escribiendo el informe';

  @override
  String get goalPhaseDone => 'hecho';

  @override
  String get goalPaused => 'En pausa';

  @override
  String get goalPausedBudget => 'En pausa: el presupuesto está agotado';

  @override
  String get goalCompleted => 'Completado';

  @override
  String get goalStopped => 'Detenido';

  @override
  String get goalFailed => 'algo salió mal';

  @override
  String get goalReady => 'Listo';

  @override
  String goalStepsOf(int done, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total pasos',
      one: '1 paso',
    );
    return '$done de $_temp0';
  }

  @override
  String goalSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fuentes',
      one: '1 fuente',
    );
    return '$_temp0';
  }

  @override
  String get goalTokensWord => 'tokens';

  @override
  String get goalToolCallsWord => 'llamadas de herramientas';

  @override
  String get goalPauseAfterStep => 'Pausa después de este paso';

  @override
  String get goalStop => 'Detener';

  @override
  String get goalContinue => 'Continuar';

  @override
  String get goalOpenChat => 'abrir chat';

  @override
  String get goalNew => 'Nuevo objetivo';

  @override
  String get goalHowMade => 'Cómo se hizo este informe';

  @override
  String get goalPastTitle => 'Objetivos anteriores';

  @override
  String get goalPastReopen => 'Ajustar o continuar';

  @override
  String drawerGoalsPast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count objetivos anteriores',
      one: '1 objetivo anterior',
    );
    return '$_temp0 · Empieza uno nuevo';
  }

  @override
  String get goalReport => 'Informe';

  @override
  String get goalInterimReport => 'Informe provisional';

  @override
  String get goalCopyReport => 'Copiar informe';

  @override
  String get goalReportCopied => 'Informe copiado';

  @override
  String get goalPlan => 'Plan';

  @override
  String get goalNotCovered => 'No cubierto por el informe';

  @override
  String get goalStillMissing => 'Aún falta';

  @override
  String get goalSourcesTitle => 'Fuentes';

  @override
  String get goalKindGeneral => 'General';

  @override
  String get goalKindGeneralHint =>
      'Cualquier tema: un informe equilibrado y citado';

  @override
  String get goalKindGeneralCriteria =>
      'Responder completamente al objetivo, con una fuente para cada afirmación';

  @override
  String get goalKindCode => 'Código';

  @override
  String get goalKindCodeHint =>
      'API, errores y bibliotecas: código funcional y versiones';

  @override
  String get goalKindCodeCriteria =>
      'Una solución funcional con código, las versiones a las que se aplica y los problemas conocidos';

  @override
  String get goalKindScience => 'Científico';

  @override
  String get goalKindScienceHint =>
      'Lo que dice la evidencia: estudios, consensos, límites';

  @override
  String get goalKindScienceCriteria =>
      'Los principales hallazgos con respecto al tipo, año y tamaño del estudio, dónde los científicos están de acuerdo y en desacuerdo, y las limitaciones.';

  @override
  String get goalKindMath => 'Matemáticas';

  @override
  String get goalKindMathHint =>
      'Definiciones, derivaciones, resultados comprobados.';

  @override
  String get goalKindMathCriteria =>
      'El resultado final, cada paso de la derivación y una verificación de la respuesta.';

  @override
  String get goalKindNews => 'Actualidad';

  @override
  String get goalKindNewsHint => 'Qué ocurrió, cuándo y qué dice cada fuente';

  @override
  String get goalKindNewsCriteria =>
      'Una cronología con fechas, las personas y organizaciones implicadas, sus posturas y qué viene después';

  @override
  String get goalKindProduct => 'Comparación de productos';

  @override
  String get goalKindProductHint => 'Comparar opciones y recomendar una';

  @override
  String get goalKindProductCriteria =>
      'Precio, especificaciones clave, fortalezas y debilidades de cada opción, y cuál se adapta a quién';

  @override
  String get drawerGoalsHint =>
      'Investigación con un plan y un informe citado.';

  @override
  String drawerGoalRunning(int step, int total) {
    return 'Ejecutando · paso $step de $total';
  }

  @override
  String drawerGoalReport(String goal) {
    return 'Informe listo · $goal';
  }

  @override
  String get emptyGoalTitle => 'Investigar una meta';

  @override
  String get emptyGoalHint =>
      'Planifica las preguntas, investiga cada una y escribe un informe citado (para código, ciencia, matemáticas, noticias o comparaciones).';

  @override
  String get composerResearchGoal => 'Investiga esto como objetivo.';

  @override
  String get composerManageShortcuts => 'Administrar';

  @override
  String get shareNothing =>
      'No hay nada que abrir en el contenido compartido.';

  @override
  String get scheduledWaiting =>
      'Su mensaje programado está en el cuadro de mensaje.';

  @override
  String get shareMore => 'Sólo se abrieron los primeros 8 archivos.';

  @override
  String shareSkipped(String names) {
    return 'No abierto (vacío o más de 64 MB): $names';
  }

  @override
  String get attachGoal => 'Investigar como objetivo';

  @override
  String get attachGoalHint => 'Un plan, varias búsquedas, un informe citado';

  @override
  String get batterySaver => 'Ahorro de batería';

  @override
  String get batterySaverOff =>
      'Respuestas más ligeras en este teléfono cuando la batería está baja o hace calor';

  @override
  String batterySaverOn(int level) {
    return 'Por debajo del $level% y sin cargar, o cuando el teléfono está caliente: sin pensar, respuestas más cortas, menos páginas leídas';
  }

  @override
  String get batterySaverLevel => 'Activar ahorro de batería por debajo de';

  @override
  String get scheduleTitle => 'Avisos programados';

  @override
  String get scheduleRowHint =>
      'Una notificación diaria que solicita un mensaje guardado cuando se toca';

  @override
  String get shortcutsTitle => 'Atajos de instrucciones';

  @override
  String get shortcutsRowHint =>
      'Escribe / en un mensaje: /summarize, /translate fr o uno de tus atajos';

  @override
  String get hostTitle => 'Utilice este dispositivo como servidor';

  @override
  String get hostRowHint => 'Compartir un modelo cargado con otro dispositivo';

  @override
  String get shortcutNew => 'Nuevo atajo';

  @override
  String get shortcutsIntro =>
      'Escriba / en el cuadro de mensaje para elegir uno. \"/summarize\" seguido de su texto envía el mensaje guardado con el texto; \"/translate fr...\" toma un idioma primero.';

  @override
  String get shortcutBuiltIn => 'incorporado';

  @override
  String shortcutDelete(String name) {
    return 'Eliminar /$name';
  }

  @override
  String get shortcutNameRule =>
      'Letras minúsculas, dígitos y guiones, hasta 24.';

  @override
  String shortcutYourVersion(String name) {
    return 'Su versión de /$name';
  }

  @override
  String shortcutEdit(String name) {
    return 'Editar /$name';
  }

  @override
  String get shortcutName => 'Nombre';

  @override
  String get shortcutDescription => 'Descripción';

  @override
  String get shortcutPrompt => 'Instrucción';

  @override
  String shortcutPromptHelp(String token) {
    return '$token se reemplaza por el texto después del comando; sin él, el texto se agrega al final.';
  }

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Guardar';

  @override
  String scheduleFailed(String error) {
    return 'No se pudo configurar el recordatorio: $error';
  }

  @override
  String get scheduleNeedsNotifications =>
      'Permitir notificaciones cuando Android lo solicite o el recordatorio no pueda aparecer.';

  @override
  String get scheduleNew => 'Nuevo';

  @override
  String get scheduleIntro =>
      'Una vez al día, a la hora que usted elija, una notificación le ofrece el mensaje. Tócalo y la aplicación te lo pregunta en un nuevo chat (o lo abre como objetivo). Nada se ejecuta en segundo plano y no se envía nada hasta que tocas.';

  @override
  String get scheduleEmpty =>
      'Aún no hay ninguno. Prueba con un resumen matinal de noticias o un objetivo semanal.';

  @override
  String get scheduleChat => 'Chat';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get scheduleNewTitle => 'Nuevo mensaje programado';

  @override
  String get commonEdit => 'Editar';

  @override
  String scheduleEveryDay(String time) {
    return 'Todos los días a las $time';
  }

  @override
  String get scheduleAskChat => 'Preguntar en un chat';

  @override
  String get scheduleOpenGoal => 'Abrir como objetivo';

  @override
  String get scheduleExample =>
      '¿Cuáles son las principales noticias en Canadá hoy?';

  @override
  String get scheduleNotificationTitle =>
      'Título de la notificación (opcional)';

  @override
  String get hostPortRange => 'Utilice un número del 1 al 65535.';

  @override
  String get hostPortReserved =>
      'Los puertos inferiores a 1024 están reservados en Android.';

  @override
  String hostCopied(String what) {
    return '$what copiado';
  }

  @override
  String get hostPickModel => 'Modelo que servir';

  @override
  String get hostPickHint =>
      'La carga tarda unos segundos. Un servidor en marcha se reinicia con el nuevo modelo; los dispositivos conectados conservan la misma dirección y el mismo token.';

  @override
  String get hostChangeModel => 'Cambiar';

  @override
  String get hostManageModels => 'Descargar o importar modelos';

  @override
  String get hostModel => 'Modelo';

  @override
  String get hostNoModel => 'Ningún modelo cargado';

  @override
  String get hostLoadFirst => 'Elige un modelo que servir.';

  @override
  String get hostModelHint =>
      'Otros dispositivos chatean con este modelo mientras el servidor se ejecuta.';

  @override
  String get hostConnection => 'Conexión';

  @override
  String get hostPort => 'Puerto';

  @override
  String get hostPortHint => 'El otro dispositivo se conecta a este puerto.';

  @override
  String get hostStarting => 'Empezando…';

  @override
  String get hostStart => 'Iniciar servidor';

  @override
  String get hostToken => 'Token de acceso';

  @override
  String get hostRotate => 'Rotar token de acceso';

  @override
  String get hostRotateHint =>
      'Los dispositivos que utilizan el token actual deben volver a conectarse con el nuevo.';

  @override
  String get hostRotated =>
      'Se usará un nuevo token la próxima vez que se inicie el servidor.';

  @override
  String get hostWaiting => 'Sirviendo · esperando solicitudes';

  @override
  String hostAnswering(String client) {
    return 'Respondiendo a $client';
  }

  @override
  String hostUp(String duration) {
    return 'activo desde hace $duration';
  }

  @override
  String get hostLive => 'en vivo';

  @override
  String get hostAnswered => 'respondidas';

  @override
  String get hostRefused => 'rechazado';

  @override
  String get hostFailed => 'fallidas';

  @override
  String get hostTokensIn => 'tokens de entrada';

  @override
  String get hostTokensOut => 'tokens de salida';

  @override
  String get hostAvgSpeed => 'velocidad promedio';

  @override
  String get hostDevices => 'dispositivos';

  @override
  String get hostBattery => 'batería';

  @override
  String get hostHeat => 'calor';

  @override
  String get hostLowBattery => 'Detener con batería baja';

  @override
  String get hostLowBatteryHint =>
      'El servidor también se detiene cuando el teléfono informa de un calor intenso. La pantalla permanece encendida mientras se ejecuta.';

  @override
  String get commonOff => 'Apagado';

  @override
  String get hostConnect => 'Conecta otro dispositivo';

  @override
  String get hostServerUrl => 'URL del servidor';

  @override
  String get hostModelId => 'ID del modelo';

  @override
  String get hostHideToken => 'Ocultar token';

  @override
  String get hostShowToken => 'Mostrar token';

  @override
  String get hostCopyConnection => 'Copiar conexión';

  @override
  String get hostPairHint =>
      'En el otro teléfono: escanee este código con la cámara y copie el texto, o pegue la conexión copiada, luego en OnDevice LLM abra Configuración > Servidor remoto > Agregar > Pegar conexión. Cualquier aplicación compatible con OpenAI también funciona, con la URL, el modelo y el token.';

  @override
  String get hostRecent => 'Solicitudes recientes';

  @override
  String get hostNoneYet => 'Ninguno todavía.';

  @override
  String hostCopy(String what) {
    return 'Copiar $what';
  }

  @override
  String hostInOut(int prompt, int completion) {
    return '$prompt entra · $completion sale';
  }

  @override
  String get remotePasteNone =>
      'El portapapeles no tiene conexión. En el otro teléfono, primero toque Copiar conexión (o escanee su código QR).';

  @override
  String remotePasted(String name) {
    return 'Se agregó $name. Active Usar servidor remoto para chatear con él.';
  }

  @override
  String get remotePaste => 'Pegar conexión';

  @override
  String get remoteAdd => 'Agregar conexión';

  @override
  String get configCopied => 'Configuración copiada como texto';

  @override
  String get configTooLarge =>
      'Ese archivo es demasiado grande para ser una configuración.';

  @override
  String get configNotAFile =>
      'Ese archivo no es una configuración del modelo OnDevice LLM.';

  @override
  String get configNotInClipboard =>
      'El portapapeles no tiene configuración de modelo. Copie uno primero.';

  @override
  String configMadeFor(String model) {
    return 'Hecho para $model';
  }

  @override
  String get configNotDownloaded =>
      'Este modelo está en el catálogo pero no descargado: consíguelo en Modelos o aplícalo a uno que tengas.';

  @override
  String get configNotOnPhone =>
      'Este modelo no está en este teléfono. Aplica la configuración a uno que sí tengas:';

  @override
  String configSameModel(String model) {
    return '$model (mismo modelo)';
  }

  @override
  String get configEmpty =>
      'Esta tarjeta no cambia ningún ajuste; el modelo usaría tu configuración actual.';

  @override
  String configLeftOut(String keys) {
    return 'Omitido (acceso web, hardware del teléfono, tamaño de contexto o desconocido): $keys';
  }

  @override
  String get configApply => 'Aplicar';

  @override
  String get hostShowQr => 'Mostrar código de emparejamiento';

  @override
  String get voiceConversation => 'Conversación de voz';

  @override
  String get chatPinModel => 'Fijar un modelo a este chat';

  @override
  String get chatPinHint =>
      'Este chat siempre responde con el modelo fijado, independientemente de lo que diga el seleccionador de modelo.';

  @override
  String get chatPinNone => 'Sin pin: usar el modelo seleccionado';

  @override
  String chatPinned(String model) {
    return '📌$model';
  }

  @override
  String get readerSummarize => 'Resumir artículo';

  @override
  String get readerKeyPoints => 'Puntos clave';

  @override
  String get readerExplain => 'Explicar simplemente';

  @override
  String readerSummarizePrompt(String url) {
    return 'Lea este artículo y resúmalo en unos breves párrafos, manteniendo exactos los nombres, cifras y fechas, y cítelo: $url';
  }

  @override
  String readerKeyPointsPrompt(String url) {
    return 'Lea este artículo y enumere sus puntos clave en viñetas breves, citándolo: $url';
  }

  @override
  String readerExplainPrompt(String url) {
    return 'Lea este artículo y explique lo que dice en lenguaje sencillo para alguien nuevo en el tema, citándolo: $url';
  }

  @override
  String get readerNeedsWeb =>
      'Para leer un enlace, activa la investigación web con el icono del globo.';

  @override
  String get saveToKnowledge => 'Guardar en la biblioteca';

  @override
  String get knowledgeSaveHint =>
      'Elige una colección y los mensajes que quieras guardar. Solo se incluyen el texto visible y los enlaces a las fuentes; el razonamiento privado queda excluido.';

  @override
  String get knowledgeCollectionName => 'Nombre de la colección';

  @override
  String get knowledgeDocumentTitle => 'Título del documento';

  @override
  String get knowledgeSelectMessages => 'Mensajes que se guardarán';

  @override
  String get knowledgeChatTitle => 'Conversación guardada';

  @override
  String get knowledgeNameRequired =>
      'Introduce un nombre de colección y un título de documento.';

  @override
  String knowledgeSaved(String collection) {
    return 'Guardado en $collection.';
  }

  @override
  String knowledgeSaveFailed(String error) {
    return 'No se pudo guardar en la biblioteca: $error';
  }

  @override
  String get you => 'Tú';

  @override
  String get assistant => 'Asistente';

  @override
  String get backupPasswordTooShort =>
      'Usa al menos 12 caracteres para la contraseña de la copia de seguridad.';

  @override
  String get backupPasswordsMismatch => 'Las contraseñas no coinciden.';

  @override
  String get backupSaveDialog => 'Guardar copia de seguridad cifrada';

  @override
  String get backupSaveCancelled => 'Guardado cancelado.';

  @override
  String get backupSavedNotice =>
      'Copia cifrada guardada. Conserva la contraseña: no se puede recuperar.';

  @override
  String backupFailedNotice(String error) {
    return 'Error al crear la copia: $error';
  }

  @override
  String get backupEnterPassword => 'Introduce la contraseña de la copia.';

  @override
  String get backupReplaceQuestion =>
      '¿Reemplazar la biblioteca de este dispositivo?';

  @override
  String get backupReplaceHint =>
      'Al restaurar, se reemplazarán los chats, la biblioteca, los archivos adjuntos y los ajustes al reiniciar la aplicación. Los modelos locales y las claves API guardadas no están incluidos.';

  @override
  String get backupRestoreAction => 'Restaurar';

  @override
  String get backupTooLarge => 'La copia supera el límite de seguridad.';

  @override
  String get backupVerifiedNotice =>
      'Copia verificada. Cierra por completo la aplicación y vuelve a abrirla para aplicar la restauración.';

  @override
  String backupRestoreFailed(String error) {
    return 'Error al restaurar: $error';
  }

  @override
  String get backupTitle => 'Copia de seguridad cifrada';

  @override
  String get backupIntro =>
      'Guarda chats, biblioteca, archivos adjuntos, objetivos y ajustes en un archivo protegido con contraseña. Los modelos y las claves API permanecen en este dispositivo. El límite es de 96 MB.';

  @override
  String get backupPasswordLabel => 'Contraseña de la copia';

  @override
  String get backupConfirmPassword =>
      'Confirma la contraseña de la nueva copia';

  @override
  String get backupCreateAction => 'Crear copia de seguridad cifrada';

  @override
  String get backupRestoreBackup => 'Restaurar copia de seguridad';

  @override
  String get uiRemoteProfilePageDeleteConnection => '¿Eliminar conexión?';

  @override
  String get uiRemoteProfilePageCancel => 'Cancelar';

  @override
  String get uiRemoteProfilePageDelete => 'Eliminar';

  @override
  String get uiRemoteProfilePageConnection => 'Conexión';

  @override
  String get uiRemoteProfilePageThisConnectionWasRemoved =>
      'Esta conexión fue eliminada.';

  @override
  String get uiRemoteProfilePageDeleteConnection2 => 'Eliminar conexión';

  @override
  String get uiRemoteProfilePageProvider => 'Proveedor';

  @override
  String get uiRemoteProfilePageName => 'Nombre';

  @override
  String get uiRemoteProfilePageServerURL => 'URL del servidor';

  @override
  String get uiRemoteProfilePageGetAKeyInTheBrowser =>
      'Obtener una clave en el navegador';

  @override
  String get uiRemoteProfilePageModel => 'modelo';

  @override
  String get uiRemoteProfilePageModelsOnTheServer => 'Modelos en el servidor.';

  @override
  String get uiRemoteProfilePageRequestsPerMinute => 'Solicitudes por minuto';

  @override
  String get uiRemoteProfilePageNone => 'ninguno';

  @override
  String get uiRemoteProfilePageRequestsPerDay => 'Solicitudes por día';

  @override
  String get uiRemoteProfilePageExtraHeaders => 'encabezados adicionales';

  @override
  String get uiAdvancedPagesContextBatch => 'Contexto y lote';

  @override
  String get uiAdvancedPagesContextSize => 'Tamaño del contexto';

  @override
  String get uiAdvancedPagesTokensTheModelCanSeeAt =>
      'Tokens que el modelo puede ver a la vez: la conversación, la evidencia web y la respuesta. La memoria crece con ella; si el teléfono no puede retenerla, el modelo se carga con un contexto más corto y una nota lo indica.';

  @override
  String get uiAdvancedPagesContextSizeTokens => 'Tamaño del contexto (tokens)';

  @override
  String get uiAdvancedPagesBatchSize => 'Tamaño del lote';

  @override
  String get uiAdvancedPagesPromptTokensSubmittedPerStepAuto =>
      'Tokens de aviso enviados por paso. Auto es 512, el óptimo medido en este teléfono; más grande ayuda principalmente a que la GPU prellene mensajes largos.';

  @override
  String get uiAdvancedPagesMicroBatch => 'Microlote';

  @override
  String get uiAdvancedPagesTokensPerComputeStepWithinA =>
      'Tokens por paso de cálculo dentro de un lote. Auto coincide con el tamaño del lote. Nunca por encima del tamaño del lote.';

  @override
  String get uiAdvancedPagesKeepConversationInContext =>
      'Mantenga la conversación en contexto';

  @override
  String get uiAdvancedPagesOnlyNewTextIsEvaluatedOn =>
      'Sólo se evalúa el texto nuevo en cada turno; turnos anteriores permanecen residentes. Off vuelve a leer toda la conversación en cada mensaje.';

  @override
  String get uiAdvancedPagesHardware => 'Hardware';

  @override
  String get uiAdvancedPagesBackend => 'backend';

  @override
  String get uiAdvancedPagesAutomaticUsesCPUOpenCL2Faster =>
      'Automático utiliza CPU. OpenCL: ~2 veces más rápida lectura rápida para investigación, ~15 % respuestas más lentas; El modelo se recarga cuando lo cambias.';

  @override
  String get uiAdvancedPagesGPULayers => 'capas de GPU';

  @override
  String get uiAdvancedPagesLayersOffloadedToTheGPUIgnored =>
      'Capas descargadas a la GPU. Se ignora cuando el backend es solo CPU.';

  @override
  String get uiAdvancedPagesCPUThreadsDecode => 'Hilos de CPU (decodificar)';

  @override
  String get uiAdvancedPagesWorkerThreadsWhileTheAnswerStreams =>
      'El trabajador enhebra mientras se transmite la respuesta. Auto usa 6 en teléfonos de 8 núcleos (medido más rápido); de lo contrario, la mitad de los núcleos.';

  @override
  String get uiAdvancedPagesCPUThreadsPrefill =>
      'Subprocesos de CPU (precarga)';

  @override
  String get uiAdvancedPagesThreadsWhileThePromptIsRead =>
      'Hilos mientras se lee el mensaje. Auto utiliza todos los núcleos: el prellenado siguió acelerando hasta 8 subprocesos donde la decodificación se ralentizó.';

  @override
  String get uiAdvancedPagesFlashAttention => 'Atención flash';

  @override
  String get uiAdvancedPagesFasterAttentionKernelWithLowerMemory =>
      'Núcleo de atención más rápido con menor uso de memoria.';

  @override
  String get uiAdvancedPagesKVCache => 'caché KV';

  @override
  String get uiAdvancedPagesPrecisionOfCachedAttentionState =>
      'Precisión del estado de atención en caché';

  @override
  String get uiAdvancedPagesSampling => 'Muestreo';

  @override
  String get uiAdvancedPagesTemperature => 'Temperatura';

  @override
  String get uiAdvancedPagesRandomnessLowerIsMoreFocusedHigher =>
      'Aleatoriedad. Lo más bajo es más enfocado, lo más alto es más variado.';

  @override
  String get uiAdvancedPagesTopP => 'Top-P';

  @override
  String get uiAdvancedPagesSampleFromTheSmallestSetOf =>
      'Elige entre el conjunto más pequeño de tokens cuyas probabilidades suman P.';

  @override
  String get uiAdvancedPagesMinP => 'Min-P';

  @override
  String get uiAdvancedPagesDropTokensLessLikelyThanThis =>
      'Descarta los tokens cuya probabilidad sea menor que esta fracción de la del token más probable.';

  @override
  String get uiAdvancedPagesTopK => 'Top-K';

  @override
  String get uiAdvancedPagesOnlyTheKMostLikelyTokens =>
      'Solo se consideran los K tokens más probables. 0 lo desactiva.';

  @override
  String get uiAdvancedPagesRepetitionPenalty => 'Penalización por repetición';

  @override
  String get uiAdvancedPagesDiscouragesRepeatingRecentTokens100 =>
      'Desalienta la repetición de tokens recientes. 1.00 está apagado.';

  @override
  String get uiAdvancedPagesMaxTokens => 'Máximo de tokens';

  @override
  String get uiAdvancedPagesUpperBoundOnOneResponseReasoning =>
      'Límite superior de una respuesta, incluido el razonamiento. Está reservado dentro del contexto, por lo que debe encajar junto al mensaje.';

  @override
  String get uiAdvancedPagesMaxTokensPerResponse =>
      'Tokens máximos por respuesta';

  @override
  String get uiAdvancedPagesReasoningSearch => 'Razonamiento y búsqueda';

  @override
  String get uiAdvancedPagesThinkingMode => 'Modo de pensamiento';

  @override
  String get uiAdvancedPagesShowModelGeneratedReasoningWhenSupported =>
      'Muestre el razonamiento generado por el modelo cuando sea compatible. Puede contener errores y no es prueba de corrección.';

  @override
  String get uiAdvancedPagesThinkingBudget => 'Presupuesto de razonamiento';

  @override
  String get uiAdvancedPagesReasoningTokensAllowedBeforeTheBlock =>
      'Se permiten fichas de razonamiento antes de que se cierre el bloque y comience la respuesta. Limita la espera a cuestiones difíciles; ilimitado deja que el modelo decida.';

  @override
  String get uiAdvancedPagesThinkingBudgetTokens0Unlimited =>
      'Presupuesto de pensamiento (tokens, 0 = ilimitado)';

  @override
  String get uiAdvancedPagesSearchAndNewsRegion =>
      'Región de búsqueda y noticias.';

  @override
  String get uiAdvancedPagesSearchResults => 'Resultados de la búsqueda';

  @override
  String get uiAdvancedPagesCandidatesTakenFromDuckDuckGoPerQuery =>
      'Candidatos tomados de DuckDuckGo por consulta.';

  @override
  String get uiAdvancedPagesPagesToRead => 'paginas para leer';

  @override
  String get uiAdvancedPagesResultPagesFetchedAndRankedFor =>
      'Páginas de resultados recuperadas y clasificadas como evidencia. Las páginas ilegibles se omiten para el siguiente candidato. Más es más lento y utiliza más contexto.';

  @override
  String get uiAdvancedPagesResearchTimeBudget =>
      'Presupuesto de tiempo de investigación';

  @override
  String get uiAdvancedPagesWallClockLimitForReadingAll =>
      'Límite de reloj de pared para leer todas las páginas de una pregunta. Los sitios lentos se cortan al límite y la respuesta continúa con lo leído.';

  @override
  String get uiAdvancedPagesModelDrivenResearchExperimental =>
      'Investigación basada en modelos (experimental)';

  @override
  String get uiAdvancedPagesModelWritesTheSearchQueries =>
      'El modelo escribe las consultas de búsqueda.';

  @override
  String get uiAdvancedPagesTheLocalModelTurnsYourQuestion =>
      'El modelo local convierte su pregunta en una o dos consultas en el motor de búsqueda antes de realizar la búsqueda. Cuesta unos segundos; off envía la pregunta tal como se escribió.';

  @override
  String get uiAdvancedPagesPassagesGivenToTheModel =>
      'Pasajes dados al modelo.';

  @override
  String get uiAdvancedPagesBestMatchingPassagesAbout250Tokens =>
      'Pasajes que mejor coinciden (alrededor de 250 tokens cada uno) en todas las páginas leídas. Más evidencia, prellenado más largo.';

  @override
  String get uiAdvancedPagesFlagUnsupportedFigures =>
      'Marcar figuras no admitidas';

  @override
  String get uiAdvancedPagesAfterAGroundedAnswerNumbersVersions =>
      'Después de una respuesta fundamentada, los números, versiones y fechas que no aparecen en ningún pasaje proporcionado se consideran no verificados.';

  @override
  String get supportCheckTitle => 'Comprobar frases por el sentido';

  @override
  String get supportCheckHint =>
      'Un modelo pequeño (Qwen3 Reranker 0.6B) lee el pasaje de la fuente más cercano antes de marcar una frase, así una frase correcta dicha con otras palabras no se marca como no respaldada. Descarga aparte; funciona unos segundos tras una respuesta con fuentes.';

  @override
  String get uiHfSearchPageSearchHuggingFace => 'Buscar en Hugging Face';

  @override
  String get uiHfSearchPageModelNameEGQwen34B =>
      'Nombre del modelo, p. ej., Qwen3 4B, Phi-4, Llama 3.2';

  @override
  String get uiHfSearchPageNoGGUFRepositoriesMatch =>
      'Ningún repositorio GGUF coincide.';

  @override
  String get uiHfSearchPageNoSingleFileGGUFWeightsIn =>
      'No hay pesos GGUF de un solo archivo en este repositorio.';

  @override
  String get uiHfSearchPageNotAddableHere => 'No se puede agregar aquí';

  @override
  String get uiBenchmarkDialogBenchmarkCopied =>
      'Prueba de rendimiento copiada';

  @override
  String get uiBenchmarkDialogCopy => 'Copiar';

  @override
  String get uiBenchmarkDialogShare => 'Compartir';

  @override
  String get uiBenchmarkDialogDone => 'hecho';

  @override
  String get uiModelReadinessPageModelReadiness => 'Preparación del modelo';

  @override
  String get uiModelReadinessPageDeviceCapacity => 'Capacidad del dispositivo';

  @override
  String get uiModelReadinessPagePhysicalRAM => 'RAM física';

  @override
  String get uiModelReadinessPageModelStorageVolume =>
      'Volumen de almacenamiento del modelo';

  @override
  String get uiModelReadinessPageInstalledModelWeights =>
      'Pesos de modelos instalados';

  @override
  String get uiModelReadinessPageCurrentContextAndBackend =>
      'Contexto actual y backend';

  @override
  String get uiModelReadinessPageModels => 'Modelos';

  @override
  String get uiModelReadinessPageRAMFitIsARoughEstimate =>
      'El ajuste de RAM es una estimación aproximada. La memoria de contexto y la velocidad reales dependen del modelo, el backend y la temperatura del dispositivo.';

  @override
  String get uiToolsQuickPanelLetTheModelCallTools =>
      'Deje que el modelo llame a las herramientas';

  @override
  String get uiToolsQuickPanelTHISMODELMAYCALL => 'Este modelo puede llamar';

  @override
  String get uiToolsQuickPanelCalculator => 'calculadora';

  @override
  String get uiToolsQuickPanelExactArithmetic => 'Aritmética exacta.';

  @override
  String get uiToolsQuickPanelSearchWebReadUrlFindIn =>
      'search_web · read_url · find_in_page';

  @override
  String get uiToolsQuickPanelSearchDocuments => 'search_documents';

  @override
  String get uiToolsQuickPanelToolUse => 'uso de herramientas';

  @override
  String get uiToolsQuickPanelAuto => 'Automático';

  @override
  String get uiToolsQuickPanelRequired => 'Requerido';

  @override
  String get uiAdvancedAdaptersPageLoRAAdapters => 'Adaptadores LoRA';

  @override
  String get uiAdvancedAdaptersPageImportAdapter => 'Importar adaptador';

  @override
  String get uiAdvancedAdaptersPageDelete => 'Eliminar';

  @override
  String get uiAdvancedAppearancePageAppearance => 'Apariencia';

  @override
  String get uiAdvancedAppearancePageTheme => 'Tema';

  @override
  String get uiAdvancedAppearancePageDarkIsTheDesignedDefaultLight =>
      'El tema oscuro es el predeterminado; si eliges Sistema, el tema claro sigue el ajuste del teléfono.';

  @override
  String get uiAdvancedAppearancePageAccentColour => 'Color de acento';

  @override
  String get uiAdvancedAppearancePageTextSize => 'Tamaño del texto';

  @override
  String get uiAdvancedAppearancePageCompactBubbles => 'Burbujas compactas';

  @override
  String get uiAdvancedAppearancePageTighterSpacingInTheConversation =>
      'Espaciamiento más estrecho en la conversación.';

  @override
  String get motionLabel => 'Animación';

  @override
  String get motionHint =>
      'Muelles, controles que se transforman y desenfoques suaves. El ajuste Eliminar animaciones del teléfono la desactiva.';

  @override
  String get motionFull => 'Completa';

  @override
  String get motionSubtle => 'Sutil';

  @override
  String get motionOff => 'Desactivada';

  @override
  String islandLoadingModel(String model) {
    return 'Cargando $model';
  }

  @override
  String get islandModelReady => 'Modelo listo';

  @override
  String get islandResearchDone => 'Investigación lista';

  @override
  String get islandAnswered => 'Respuesta lista';

  @override
  String get jumpToLatest => 'Ir al último mensaje';

  @override
  String get uiAdvancedMemoryRopePageMemoryRoPESpeculation =>
      'Memoria, RoPE y especulación';

  @override
  String get uiAdvancedMemoryRopePageKCache => 'caché K';

  @override
  String get uiAdvancedMemoryRopePagePrecisionOfCachedKeys =>
      'Precisión de claves en caché';

  @override
  String get uiAdvancedMemoryRopePageVCache => 'caché V';

  @override
  String get uiAdvancedMemoryRopePagePrecisionOfCachedValuesQuantisingV =>
      'Precisión de los valores almacenados en caché. La cuantificación de V necesita atención flash, que se habilita automáticamente.';

  @override
  String get uiAdvancedMemoryRopePageRoPEScaling => 'Escalado de RoPE';

  @override
  String get uiAdvancedMemoryRopePageHowPositionsBeyondTheTrainedContext =>
      'Cómo se amplían las posiciones más allá del contexto capacitado. \"Modelo\" mantiene lo que declara el GGUF; YaRN es la opción habitual para contextos más largos en modelos que lo admiten.';

  @override
  String get uiAdvancedMemoryRopePageRoPEFrequencyBase =>
      'Frecuencia base de RoPE';

  @override
  String get uiAdvancedMemoryRopePageEG1000000ForModelsThat =>
      'por ej. 1000000 para modelos que lo documenten';

  @override
  String get uiAdvancedMemoryRopePageRoPEFrequencyScale =>
      'Escala de frecuencia de RoPE';

  @override
  String get uiAdvancedMemoryRopePage0Scale1EG0 =>
      '0 < escala ≤ 1, p.e. 0,25 para 4 veces el contexto entrenado';

  @override
  String get uiAdvancedMemoryRopePageYaRNOriginalContext =>
      'Contexto original de YaRN';

  @override
  String get uiAdvancedMemoryRopePageTheContextTheModelWasTrained =>
      'El contexto para el que se entrenó el modelo';

  @override
  String get uiAdvancedMemoryRopePageYaRNExtrapolationMix =>
      'Mezcla de extrapolación de YaRN';

  @override
  String get uiAdvancedMemoryRopePage0InterpolationOnly1FullExtrapolation =>
      '0 = solo interpolación, 1 = extrapolación completa';

  @override
  String get uiAdvancedMemoryRopePageYaRNAttentionFactor =>
      'Factor de atención de YaRN';

  @override
  String get uiAdvancedMemoryRopePageMagnitudeScalingUsually10 =>
      'Escala de magnitud, generalmente 1,0';

  @override
  String get uiAdvancedMemoryRopePageYaRNBetaFast => 'YaRN beta rápido';

  @override
  String get uiAdvancedMemoryRopePageLowCorrectionDimension =>
      'Dimensión de corrección baja';

  @override
  String get uiAdvancedMemoryRopePageYaRNBetaSlow => 'YaRN beta lento';

  @override
  String get uiAdvancedMemoryRopePageHighCorrectionDimension =>
      'Alta dimensión de corrección';

  @override
  String get uiAdvancedMemoryRopePageDraftModel => 'Modelo borrador';

  @override
  String get uiAdvancedMemoryRopePageASmallerModelWithTheSame =>
      'Un modelo más pequeño con el mismo vocabulario propone varios tokens; el modelo principal los verifica en una sola pasada. Ayuda con respuestas largas y predecibles; mídalo: cuesta memoria y puede ser más lento.';

  @override
  String get uiAdvancedMemoryRopePageDraftTokensPerRound =>
      'Tokens del borrador por ronda';

  @override
  String get uiAdvancedMemoryRopePageHowManyTokensTheDraftProposes =>
      'Cuántos tokens propone el borrador antes de la verificación. Lo más alto gana más cuando el draft es correcto y desperdicia más cuando es incorrecto.';

  @override
  String get uiAdvancedPages2Cancel => 'Cancelar';

  @override
  String get uiAdvancedPages2NotAValidValue => 'No es un valor válido.';

  @override
  String get uiAdvancedPages2Save => 'Guardar';

  @override
  String get uiAdvancedSamplingPageMoreSampling => 'Más muestreo';

  @override
  String get uiAdvancedSamplingPageSeed => 'semilla';

  @override
  String get uiAdvancedSamplingPageSeed0Random => 'Semilla (0 = aleatorio)';

  @override
  String get uiAdvancedSamplingPageStopSequences => 'Detener secuencias';

  @override
  String get uiAdvancedSamplingPagePresencePenalty =>
      'Penalización de presencia';

  @override
  String get uiAdvancedSamplingPageOnceATokenHasAppearedIt =>
      'Una vez que ha aparecido un token, no se recomienda hacerlo, independientemente de la frecuencia con la que se utilice. 0 está apagado; los negativos fomentan la reutilización.';

  @override
  String get uiAdvancedSamplingPageFrequencyPenalty =>
      'Penalización de frecuencia';

  @override
  String get uiAdvancedSamplingPageEachRepetitionAddsToThePenalty =>
      'Cada repetición aumenta la penalización. 0 la desactiva.';

  @override
  String get uiAdvancedSamplingPagePenaltyWindow => 'Ventana de penalización';

  @override
  String get uiAdvancedSamplingPageHowManyRecentTokensTheRepetition =>
      'Cuántos tokens recientes analizan las penalizaciones por repetición, presencia y frecuencia. 0 los apaga.';

  @override
  String get uiAdvancedSamplingPageDRYMultiplier => 'Multiplicador DRY';

  @override
  String get uiAdvancedSamplingPageDRYPenalisesRepeatingWholeSequencesRather =>
      'DRY penaliza la repetición de secuencias completas en lugar de tokens individuales. 0 está apagado; 0,8 es la fuerza habitual.';

  @override
  String get uiAdvancedSamplingPageDRYBase => 'Base DRY';

  @override
  String get uiAdvancedSamplingPageGrowthOfThePenaltyWithThe =>
      'Cómo crece la penalización con la longitud repetida.';

  @override
  String get uiAdvancedSamplingPageDRYAllowedLength =>
      'Longitud permitida por DRY';

  @override
  String get uiAdvancedSamplingPageRepeatsShorterThanThisAreFree =>
      'Las repeticiones más cortas no se penalizan.';

  @override
  String get uiAdvancedSamplingPageTypicalP => 'Típico-P';

  @override
  String get uiAdvancedSamplingPageKeepsTokensWhoseSurpriseIsClose =>
      'Mantiene tokens cuya sorpresa se acerca a la esperada. 1.00 está apagado.';

  @override
  String get uiAdvancedSamplingPageXTCProbability => 'probabilidad XTC';

  @override
  String get uiAdvancedSamplingPageWithThisProbabilityTheMostLikely =>
      'Con esta probabilidad se eliminan los tokens más probables por encima del umbral, excepto el último, para una prosa más variada. 0 está apagado.';

  @override
  String get uiAdvancedSamplingPageXTCThreshold => 'Umbral XTC';

  @override
  String get uiAdvancedSamplingPageTokensAboveThisProbabilityAreCandidates =>
      'Los tokens por encima de esta probabilidad son candidatos a ser eliminados.';

  @override
  String get uiAdvancedSamplingPageTopNSigma => 'Top-n-sigma';

  @override
  String get uiAdvancedSamplingPageKeepsTokensWithinNStandardDeviations =>
      'Mantiene los tokens dentro de n desviaciones estándar del mejor logit; Funciona bien con altas temperaturas. Apagado a las 0.';

  @override
  String get uiAdvancedSamplingPageResetOrder => 'Restablecer orden';

  @override
  String get uiAdvancedSamplingPageOnePerLineUpTo8 =>
      'Uno por línea, hasta 8. La respuesta termina cuando aparece uno; nunca se muestra.';

  @override
  String get uiAdvancedSamplingPageCancel => 'Cancelar';

  @override
  String get uiAdvancedSamplingPageSave => 'Guardar';

  @override
  String get uiAdvancedStructuredOutputPageStructuredOutput =>
      'Salida estructurada';

  @override
  String get uiAdvancedStructuredOutputPageResponseFormat =>
      'Formato de respuesta';

  @override
  String
  get uiAdvancedStructuredOutputPageConstrainsEveryTokenTheModelProduces =>
      'Restringe cada token que produce el modelo. El pensamiento se desactiva ante respuestas limitadas y no se ofrecen herramientas.';

  @override
  String get uiAdvancedStructuredOutputPageJSONSchema => 'Esquema JSON';

  @override
  String get uiAdvancedStructuredOutputPageGBNFGrammar => 'Gramática GBNF';

  @override
  String get uiAdvancedStructuredOutputPageCancel => 'Cancelar';

  @override
  String get uiAdvancedStructuredOutputPageSave => 'Guardar';

  @override
  String get uiAdvancedToolsPageTools => 'Herramientas';

  @override
  String get uiAdvancedToolsPageLetTheModelCallTools =>
      'Deje que el modelo llame a las herramientas';

  @override
  String get uiAdvancedToolsPageTheModelCanDecideToSearch =>
      'El modelo puede decidir buscar en la web, leer una página, buscar en sus documentos o calcular y luego responder a partir de los resultados. Cada herramienta se mantiene detrás de su propio permiso a continuación.';

  @override
  String get uiAdvancedToolsPageToolUse => 'uso de herramientas';

  @override
  String get uiAdvancedToolsPageAutoLetsTheModelDecideWhether =>
      'Auto permite que el modelo decida si se necesita una herramienta. Requerido hace que llame a uno antes de su primera respuesta (las rondas posteriores dependen nuevamente de él): úselo cuando el modelo siga respondiendo de memoria en lugar de buscar.';

  @override
  String get uiAdvancedToolsPageRoundsPerAnswer => 'Rondas por respuesta';

  @override
  String get uiAdvancedToolsPageHowManyTimesTheModelMay =>
      'Cuántas veces el modelo puede llamar a las herramientas antes de responder. Cada ronda es otro pase modelo.';

  @override
  String get uiAdvancedToolsPageCalculator => 'calculadora';

  @override
  String get uiAdvancedToolsPageExactArithmeticNoPermissionNeeded =>
      'Aritmética exacta. No se necesita permiso.';

  @override
  String get uiAdvancedToolsPageSearchWebReadUrlFindIn =>
      'search_web · read_url · find_in_page';

  @override
  String get uiAdvancedToolsPageSearchDocuments => 'search_documents';

  @override
  String get uiEffectiveSettingsPageEffectiveSettings =>
      'Configuraciones efectivas';

  @override
  String get uiEffectiveSettingsPageAppliesWhenTheModelLoads =>
      'Se aplica cuando se carga el modelo.';

  @override
  String get uiEffectiveSettingsPageClose => 'Cerrar';

  @override
  String get uiKnowledgePageOK => 'bien';

  @override
  String get uiKnowledgePageVerifying => 'Verificando…';

  @override
  String get uiMemoryPageEGTheUserIsA =>
      'por ej. El usuario es enfermero en Lisboa y prefiere unidades métricas.';

  @override
  String get uiOverridesPageClearAll => 'Borrar todo';

  @override
  String get uiOverridesPageInherit => 'heredar';

  @override
  String get uiOverridesPageOn => 'encendido';

  @override
  String get uiOverridesPageOff => 'Apagado';

  @override
  String get uiOverridesPageCancel => 'Cancelar';

  @override
  String get uiOverridesPageNotAValidValue => 'No es un valor válido.';

  @override
  String get uiOverridesPageSave => 'Guardar';

  @override
  String get uiRemoteServerPageUseRemoteServer => 'Usar servidor remoto';

  @override
  String get uiRemoteServerPageNoConnectionsYet => 'Aún no hay conexiones';

  @override
  String get uiRemoteServerPageAddOneToChooseAProvider =>
      'Agregue uno para elegir un proveedor, URL, clave API y modelo.';

  @override
  String get uiRemoteServerPageEditConnection => 'Editar conexión';

  @override
  String get uiRemoteServerPageWebResearch => 'investigación web';

  @override
  String get uiRemoteServerPageTheAppSearchesDuckDuckGoAndReads =>
      'El modelo remoto decide si una pregunta necesita la web, escribe sus propias búsquedas y elige las páginas que lee; la aplicación las ejecuta en DuckDuckGo y Wikipedia sin clave.';

  @override
  String get uiRemoteServerPageImageUnderstanding => 'Comprensión de imágenes';

  @override
  String get uiRemoteServerPageSendAttachedImagesToTheModel =>
      'Enviar imágenes adjuntas al modelo. Habilítelo solo para un modelo con capacidad de visión.';

  @override
  String get uiRemoteServerPageDocumentUnderstanding =>
      'Comprensión del documento';

  @override
  String get uiRemoteServerPageExtractDocumentsSafelyOnThePhone =>
      'Extraiga documentos de forma segura en el teléfono y luego envíe su texto cuando se le solicite. Los archivos originales no se cargan.';

  @override
  String get uiRemoteServerPageStreamingIdleTimeout =>
      'Tiempo de espera de inactividad de transmisión';

  @override
  String get uiRemoteServerPageHowLongToWaitBetweenResponse =>
      'Cuánto tiempo esperar entre fragmentos de respuesta de un servidor lento o muy cargado.';

  @override
  String get uiRemoteServerPageChooseAProvider => 'Elige un proveedor';

  @override
  String get uiSettingsScreenEncryptedBackup => 'Copia de seguridad cifrada';

  @override
  String get uiSettingsScreenMoreSampling => 'Más muestreo';

  @override
  String get uiSettingsScreenMemoryRoPESpeculation =>
      'Memoria, RoPE y especulación';

  @override
  String get uiSettingsScreenStructuredOutput => 'Salida estructurada';

  @override
  String get uiSettingsScreenTools => 'Herramientas';

  @override
  String get uiSettingsScreenLoRAAdapters => 'Adaptadores LoRA';

  @override
  String get uiSettingsScreenEffectiveSettings => 'Configuraciones efectivas';

  @override
  String get uiSettingsScreenAppearance => 'Apariencia';

  @override
  String get uiMetricsSheetInstrumentPanel => 'Panel de instrumentos';

  @override
  String get uiMetricsSheetDisplay => 'Pantalla';

  @override
  String get uiMetricsSheetBenchmarkThisModel =>
      'Probar rendimiento de este modelo';

  @override
  String get uiMetricsSheetMeasuredOnThisDeviceNothingIs =>
      'Medido en este dispositivo. No se transmite nada.';

  @override
  String get uiMetricsSheetSendAMessageToSeeLive =>
      'Envía un mensaje para ver números en vivo.';

  @override
  String get uiMetricsSheetBackend => 'backend';

  @override
  String get uiMetricsSheetNativeLibrary => 'biblioteca nativa';

  @override
  String get uiMetricsSheetStages => 'Etapas';

  @override
  String get uiMetricsSheetTokensSec => 'Tokens/s';

  @override
  String get uiMetricsSheetFirstToken => 'Primer token';

  @override
  String get uiMetricsSheetTokens => 'Tokens';

  @override
  String get uiMetricsSheetContext => 'Contexto';

  @override
  String get uiMetricsSheetPeakRSS => 'RSS pico';

  @override
  String get uiMetricsSheetTemplate => 'Plantilla';

  @override
  String get uiMetricsSheetThinking => 'Pensando';

  @override
  String get uiMetricsSheetModel => 'Modelo';

  @override
  String get uiSettingsWidgetsCancel => 'Cancelar';

  @override
  String get uiSettingsWidgetsApply => 'Aplicar';

  @override
  String get uiPresetSheet00Exact => '0.0 · exacto';

  @override
  String get uiPresetSheet03Focused => '0.3 · enfocado';

  @override
  String get uiPresetSheet07Balanced => '0,7 · equilibrado';

  @override
  String get uiPresetSheet10Creative => '1.0 · creativo';

  @override
  String get uiModelsScreenHttpsHuggingfaceCo => 'https://huggingface.co/…';

  @override
  String get uiModelsScreenModelReadiness => 'Preparación del modelo';

  @override
  String get uiModelsScreenImportConfiguration => 'Importar configuración';

  @override
  String get uiModelsScreenImportConfigurationFromClipboard =>
      'Importar configuración desde el portapapeles';

  @override
  String get uiModelsScreenImportConfigurationFromAFile =>
      'Importar configuración desde un archivo';

  @override
  String get uiModelsScreenShareOrImportAConfiguration =>
      'Compartir o importar una configuración';

  @override
  String get uiModelsScreenShareConfiguration => 'Compartir configuración';

  @override
  String get uiModelsScreenCopyAsText => 'Copiar como texto';

  @override
  String get uiModelsScreenImportFromClipboard =>
      'Importar desde el portapapeles';

  @override
  String get uiModelsScreenImportFromAFile => 'Importar desde un archivo';

  @override
  String get uiModelCardRemoveFromList => 'Eliminar de la lista';

  @override
  String get uiModelPickerSheetRemoteConnections => 'Conexiones remotas';

  @override
  String get uiModelPickerSheetAnswersComeFromTheConnectionInstead =>
      'Las respuestas provienen de la conexión en lugar de un modelo en este teléfono.';

  @override
  String get uiQrViewQRCodeWithTheConnectionDetails =>
      'Código QR con los datos de conexión';

  @override
  String get uiChatScreenActionsTitle => 'Título';

  @override
  String get uiChatScreenActionsDocumentType => 'Tipo de documento';

  @override
  String get uiChatScreenActionsWordDocx => 'Word (.docx)';

  @override
  String get uiChatScreenActionsPDF => 'PDF';

  @override
  String get uiChatScreenActionsPlainTextTxt => 'Texto sin formato (.txt)';

  @override
  String get uiChatScreenActionsMarkdownMd => 'Markdown (.md)';

  @override
  String get uiChatScreenActionsHTML => 'HTML';

  @override
  String get uiChatScreenActionsSelectIndividualMessages =>
      'Seleccionar mensajes individuales';

  @override
  String get uiChatScreenActionsRedactTermsCommaSeparated =>
      'Ocultar términos (separados por comas)';

  @override
  String get uiChatScreenActionsChooseMessages => 'Elige mensajes';

  @override
  String get uiChatScreenActionsUseSelection => 'Usar selección';

  @override
  String get uiChatScreenActionsReviewDocument => 'Revisar documento';

  @override
  String get uiChatBubbleChooseQuestionVersion =>
      'Elija la versión de la pregunta';

  @override
  String get uiChatBubbleSources => 'Fuentes';

  @override
  String get uiChatBubbleKnowledgeLibrary => 'Biblioteca de conocimientos';

  @override
  String get uiChatBubbleSponsoredNotUsed => 'Patrocinado (no usado)';

  @override
  String get uiChatBubbleOpenInBrowser => 'Abrir en el navegador';

  @override
  String get uiCodeBlockCopyCode => 'Copiar código';

  @override
  String get uiCodeBlockCodeCopied => 'Código copiado';

  @override
  String get readinessUnavailable => 'No disponible en este dispositivo';

  @override
  String readinessMemory(Object total, Object available) {
    return '$total en total · $available disponibles';
  }

  @override
  String readinessStorage(Object free, Object total) {
    return '$free libres de $total';
  }

  @override
  String readinessInstalledWeights(Object size, Object count) {
    return '$size en $count modelos';
  }

  @override
  String readinessContext(Object count, Object backend) {
    return '$count tokens · $backend';
  }

  @override
  String get readinessInstalled => 'Instalado';

  @override
  String readinessDownload(Object size) {
    return 'Descargar: $size';
  }

  @override
  String get readinessRamFits => 'Estimación de RAM: probablemente cabe';

  @override
  String get readinessRamMayNotFit => 'Estimación de RAM: podría no caber';

  @override
  String get readinessDiskAvailable => 'Espacio de almacenamiento disponible';

  @override
  String get readinessDiskInsufficient =>
      'El espacio de almacenamiento podría ser insuficiente';

  @override
  String readinessMeasured(Object speed) {
    return 'Medido: $speed tokens/s';
  }

  @override
  String benchmarkFailed(Object error) {
    return 'Error en la prueba de rendimiento: $error';
  }

  @override
  String benchmarkRunning(Object model, Object runs) {
    return 'Probando $model…\nCarga y luego $runs ejecuciones con unos 380 tokens de entrada y 128 tokens deterministas (se descarta la primera; se muestran las medianas), y luego un chat con el mensaje de sistema de la app, con y sin las herramientas.';
  }

  @override
  String get hfIntro =>
      'Solo repositorios GGUF públicos, ordenados por descargas. Cada archivo se vincula a una revisión y se verifica con el SHA-256 de Hub. Se muestran los proyectores de visión (mmproj) y los archivos divididos, pero aún no se pueden añadir.';

  @override
  String hfAdded(Object model, Object size, Object template) {
    return '$model añadido · $size · plantilla $template';
  }

  @override
  String get hfFromMetadata => 'de los metadatos';

  @override
  String hfRepoStats(Object downloads, Object likes) {
    return '$downloads descargas · $likes me gusta';
  }

  @override
  String get hfInLibrary => 'en la biblioteca';

  @override
  String hfLicenseRevision(Object license, Object revision) {
    return 'Licencia: $license · revisión $revision';
  }

  @override
  String get hfVisionProjector => 'proyector de visión';

  @override
  String get hfSplitFile => 'archivo dividido';

  @override
  String remoteDeleteHint(Object name) {
    return 'Se eliminarán «$name» y su clave API de este teléfono.';
  }

  @override
  String get remoteOwnServer => 'Un servidor en tu propio equipo.';

  @override
  String get remoteHostedBilling => 'API alojada facturada a tu clave.';

  @override
  String get remoteNameHelp => 'Nombre con el que se muestra esta conexión.';

  @override
  String remoteOwnUrlHelp(Object path) {
    return 'LM Studio: puerto 1234 · Ollama: 11434 · llama-server: 8080. «$path» se añade automáticamente.';
  }

  @override
  String remoteHostedUrlHelp(Object provider) {
    return 'Ya rellenado para $provider; cámbialo solo si usas un proxy o un servidor regional.';
  }

  @override
  String get remoteInvalidUrl => 'Introduce una URL http(s).';

  @override
  String get remoteApiKey => 'Clave API';

  @override
  String get remoteApiKeyOptional => 'Clave API (opcional)';

  @override
  String remoteKeyHostedHelp(Object provider) {
    return 'Se guarda en el almacén de claves de Android y solo se envía a $provider.';
  }

  @override
  String get remoteKeySelfHelp =>
      'Solo si el servidor se inició con una clave. Se guarda en el almacén de claves de Android.';

  @override
  String get remoteHideKey => 'Ocultar clave';

  @override
  String get remoteShowKey => 'Mostrar clave';

  @override
  String get remoteServerDefaultModel =>
      'Dejar vacío para usar el modelo predeterminado del servidor';

  @override
  String get remoteModelId => 'ID del modelo';

  @override
  String get remoteModelListHelp =>
      'Prueba la conexión para elegir entre los modelos disponibles.';

  @override
  String get remoteModelManualHelp =>
      'Este proveedor no ofrece una lista de modelos; introduce el ID de su documentación.';

  @override
  String get remoteTestList => 'Probar y listar modelos';

  @override
  String get remoteTestConnection => 'Probar conexión';

  @override
  String get remoteExtraHeadersHelp =>
      'Una línea «Nombre: valor» por encabezado, enviada con cada solicitud. El encabezado de la clave se añade automáticamente.';

  @override
  String get remoteConnectedNoList =>
      'Conectado. Este proveedor no ofrece una lista de modelos; introduce el ID del modelo.';

  @override
  String get remoteConnectedServerNoModels =>
      'Conectado, pero el servidor no muestra modelos. Carga uno en LM Studio o inícialo en Ollama.';

  @override
  String get remoteConnectedNoModels =>
      'Conectado, pero no hay modelos disponibles para esta clave.';

  @override
  String get remoteCapabilities => 'Capacidades';

  @override
  String get remoteRequestLimits => 'Límites de solicitudes';

  @override
  String get remoteAdvanced => 'Avanzado';

  @override
  String get remoteAnthropicNote =>
      'Anthropic: el modo de razonamiento activa el pensamiento adaptativo con resúmenes. No se envían temperatura ni top-p porque los modelos actuales los rechazan. Se admiten herramientas, imágenes y esquemas JSON.';

  @override
  String get remoteGeminiNote =>
      'Gemini: el modo de razonamiento muestra resúmenes. Se admiten llamadas a funciones, imágenes y salida JSON. Las firmas de las llamadas se conservan durante la sesión.';

  @override
  String get remoteSelfHostedNote =>
      'Conéctate solo a equipos que controles. La privacidad depende de la red: usa HTTPS o una VPN a través de Internet.';

  @override
  String remoteHostedNote(Object provider) {
    return 'Las solicitudes se facturan a tu cuenta de $provider. Establece un límite diario si compartes la clave con otras aplicaciones.';
  }

  @override
  String get remoteNoTools => 'ninguna';

  @override
  String remoteToolsDetected(Object tools) {
    return ' Herramientas del servidor detectadas: $tools; no se ejecutan automáticamente.';
  }

  @override
  String remoteContextWindow(Object count) {
    return ' Ventana de contexto: $count tokens.';
  }

  @override
  String remoteAdvertises(
    Object model,
    Object capabilities,
    Object context,
    Object tools,
  ) {
    return '$model anuncia: $capabilities.$context$tools';
  }

  @override
  String remoteContextOnly(Object model, Object count, Object tools) {
    return '$model: ventana de contexto de $count tokens.$tools';
  }

  @override
  String remoteNoCapabilities(Object tools) {
    return 'Este proveedor no anuncia las capacidades del modelo seleccionado. Ajusta las opciones de la página anterior al modelo que uses.$tools';
  }

  @override
  String get remoteDefaultModel => 'el modelo predeterminado';

  @override
  String remoteCapsHint(Object model) {
    return 'Límites para $model en esta conexión. La aplicación rechaza las solicitudes al llegar al límite; cada uso de herramientas cuenta como una solicitud. Un campo vacío significa sin límite.';
  }

  @override
  String remoteUsed(Object minute, Object day) {
    return 'Usado: $minute este minuto · $day hoy';
  }

  @override
  String remoteOtherCaps(Object models) {
    return 'Otros modelos con límites aquí: $models.';
  }

  @override
  String scheduleLoadFailed(Object error) {
    return 'No se pudieron cargar los recordatorios programados: $error';
  }

  @override
  String get noticeCheckingSearch => 'Comprobando si hace falta buscar…';

  @override
  String get noticeResearchingTools => 'Investigando con herramientas…';

  @override
  String get noticeNamingChat => 'Poniendo título al chat…';

  @override
  String get noticeSearchingAgain => 'Buscando de nuevo lo que faltaba…';

  @override
  String get noticeFollowUpSearch =>
      'Las páginas ya leídas no responden a esto. Buscando de nuevo…';

  @override
  String answerSourcesDated(String date) {
    return 'Fuentes actualizadas el $date.';
  }

  @override
  String get answerSourcesUndated =>
      'Las fuentes no dicen cuándo se actualizaron.';

  @override
  String sourceUpdated(String date) {
    return 'actualizado $date';
  }

  @override
  String get thinkOnSearchSetting => 'Pensar antes de responder con fuentes';

  @override
  String get thinkOnSearchHint =>
      'Un modelo capaz de razonar sopesa primero las páginas (hasta unos 1000 tokens), aunque el modo de pensamiento esté desactivado.';

  @override
  String get searchAgainSetting => 'Buscar de nuevo si las páginas no bastan';

  @override
  String get searchAgainHint =>
      'Cuando las páginas leídas dejan parte de la pregunta sin respuesta, una búsqueda más y hasta dos páginas más.';

  @override
  String get wikipediaLookupSetting => 'Añadir el artículo de Wikipedia';

  @override
  String get wikipediaLookupHint =>
      'El artículo de Wikipedia sobre el tema se suma a las fuentes, en el idioma de la pregunta, cuando coincide.';

  @override
  String get zimSetting => 'Wikipedia sin conexión';

  @override
  String get zimHint =>
      'Importa un archivo Kiwix .zim (de library.kiwix.org) para responder desde Wikipedia sin conexión.';

  @override
  String get zimImport => 'Importar';

  @override
  String get zimRemove => 'Quitar';

  @override
  String zimImporting(String percent) {
    return 'Copiando… $percent';
  }

  @override
  String get zimNotAZim => 'Ese archivo no es un archivo .zim.';

  @override
  String get autoTitlesSetting => 'Nombrar los chats automáticamente';

  @override
  String get autoTitlesHint =>
      'Tras la primera respuesta, el modelo da al chat un título corto. Desactivado: el primer mensaje es el título.';

  @override
  String get webModeNote =>
      'El modo de búsqueda web (Desactivado / Auto / Siempre) se ajusta en la pantalla principal de ajustes o en la pastilla del cuadro de texto.';

  @override
  String get thinkingBudgetUnlimited => 'Ilimitado';

  @override
  String get adapterImporting => 'Comprobando y copiando el adaptador…';

  @override
  String get adapterEmpty =>
      'Aún no hay adaptadores. Importa un GGUF LoRA (creado con convert_lora_to_gguf.py de llama.cpp) con +, y luego asócialo a un modelo de la misma arquitectura. El modelo se recarga con el adaptador aplicado a la escala elegida.';

  @override
  String get versionPrevious => 'Versión anterior';

  @override
  String get versionNext => 'Versión siguiente';

  @override
  String get sourceFallbackTitle => 'Fuente';

  @override
  String sourcePublished(String date) {
    return 'publicado $date';
  }

  @override
  String get sourceReadEarlier => 'leído antes';

  @override
  String get sourceMayBeOutdated => 'puede estar desactualizado';

  @override
  String get sourceSponsored => 'Resultado patrocinado';

  @override
  String get sourceSponsoredDetail =>
      'Resultado patrocinado · mostrado por transparencia · no se leyó ni se dio al modelo como prueba';

  @override
  String sourceNewsStory(String outlet) {
    return 'Noticia · $outlet';
  }

  @override
  String get sourceNewsGiven =>
      'el titular y el resumen de abajo se dieron al modelo';

  @override
  String get sourcePageRead => 'Página leída';

  @override
  String get sourceKeptCopy =>
      'copia guardada, no se pudo acceder al sitio; puede estar desactualizada';

  @override
  String get sourcePassagesGiven => 'los pasajes de abajo se dieron al modelo';

  @override
  String sourceReadFailed(String error) {
    return 'No se pudo leer la página ($error) · solo estaba disponible el fragmento de búsqueda';
  }

  @override
  String get sourceSnippetOnly =>
      'Solo el fragmento de búsqueda · la página no se leyó';

  @override
  String get sourceHeadlineOnly =>
      'Solo el título y resumen · artículo no disponible';

  @override
  String get sourceExtractedSection =>
      'Pasajes extraídos · compruebe el texto citado';

  @override
  String sourceArchiveSnapshot(String date, String language) {
    return 'Archivo sin conexión · $date · $language';
  }

  @override
  String get sourceOfflineLimitation =>
      'Este archivo no puede verificar hechos actuales o cambiantes.';

  @override
  String get sourceArchiveUnavailable =>
      'El archivo original no está disponible. Se muestra el extracto guardado.';

  @override
  String get sourceNoText => 'Sin texto.';

  @override
  String get sourceGivenHeading => 'Lo que recibió el modelo';

  @override
  String sourcePassageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fragmentos',
      one: '1 fragmento',
    );
    return '$_temp0';
  }

  @override
  String sourceReadAt(String time) {
    return 'Leída el $time';
  }

  @override
  String get sourceOpenArchived => 'Abrir el artículo sin conexión';

  @override
  String get sourceCopyLink => 'Copiar enlace';

  @override
  String get sourceLinkCopied => 'Enlace copiado';

  @override
  String get sourceAddress => 'Dirección completa';

  @override
  String sourceFromKnowledge(String title) {
    return 'De tu biblioteca de conocimiento ($title).';
  }

  @override
  String get fitFits => 'Cabe en este teléfono';

  @override
  String get fitTight => 'Justo de RAM';

  @override
  String get fitTooLarge => 'Demasiado grande para este teléfono';

  @override
  String get configApplyNote =>
      'Aplicar reemplaza el perfil de ese modelo. La búsqueda web y el hardware quedan como los configuraste.';

  @override
  String configApplied(String model) {
    return 'Aplicado a $model. Surte efecto en la próxima respuesta.';
  }

  @override
  String get storageUnavailable => 'No disponible en este dispositivo';

  @override
  String modelProfileTitle(String model) {
    return 'Perfil de $model';
  }

  @override
  String get modelProfileScope => 'Perfil del modelo';

  @override
  String conversationsLoadFailed(String error) {
    return 'No se pudieron cargar las conversaciones.\n$error';
  }

  @override
  String get adapterUnknownArchitecture => 'arquitectura desconocida';

  @override
  String adapterAppliedAt(String scale) {
    return 'Aplicado a escala $scale';
  }

  @override
  String get adapterNotApplied => 'No aplicado';

  @override
  String get noticeUpdatingMemory => 'Actualizando la memoria…';

  @override
  String noticeWeatherLoading(String place) {
    return 'Tiempo en $place desde DuckDuckGo…';
  }

  @override
  String noticeWeatherDone(String place) {
    return 'Tiempo en $place desde DuckDuckGo (Apple WeatherKit).';
  }

  @override
  String get noticeCollectingNews => 'Reuniendo las últimas noticias…';

  @override
  String get noticeWebOffUnverified =>
      'La búsqueda web está desactivada. La información actual no se ha verificado.';

  @override
  String get noticeOpeningStory => 'Abriendo esa noticia…';

  @override
  String get noticeStopping => 'Deteniendo…';

  @override
  String get noticeSearching => 'Buscando en DuckDuckGo…';

  @override
  String get noticeCheckingWikipedia => 'Consultando Wikipedia…';

  @override
  String noticeRecallArticle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fuentes anteriores',
      one: '1 fuente anterior',
    );
    return 'Se leyó el artículo de esa noticia, más $_temp0 de este chat.';
  }

  @override
  String noticeRecallPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas ya leídas',
      one: '1 página ya leída',
    );
    return 'Respondiendo con $_temp0 en este chat.';
  }

  @override
  String get noticeImageRemoteOff =>
      'La entrada de imágenes está desactivada para el servidor remoto. Actívala en los ajustes del servidor remoto si el modelo elegido admite visión.';

  @override
  String get noticeImageNoVision =>
      'Este modelo no puede ver fotos. Añade su archivo de visión en Modelos o elige un modelo con visión.';

  @override
  String noticeKnowledgeDocs(int count, String collection) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documentos',
      one: '1 documento',
    );
    return '$_temp0 de «$collection»';
  }

  @override
  String noticePlusWebResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados web',
      one: '1 resultado web',
    );
    return ' y $_temp0';
  }

  @override
  String noticeUsingTool(String tool, String args) {
    return 'Usando $tool$args…';
  }

  @override
  String get noticeStopped =>
      'Generación detenida. Se conservó la respuesta parcial.';

  @override
  String noticeTrimmed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se omitieron $count mensajes anteriores',
      one: 'Se omitió 1 mensaje anterior',
    );
    return '$_temp0 del contexto del modelo; siguen en tu historial.';
  }

  @override
  String noticeTokenLimit(int count) {
    return 'La respuesta se detuvo en el límite de $count tokens. Toca Continuar o aumenta Tokens máximos en Ajustes > Muestreo.';
  }

  @override
  String get noticeStopSequence =>
      'La respuesta terminó en una secuencia de parada.';

  @override
  String get noticeResearchSkipped =>
      'El modelo respondió sin buscar, así que nada se verificó en este turno. Regenera o desactiva la investigación guiada por el modelo para usar la búsqueda fija.';

  @override
  String get noticeNoSourcesWebOff =>
      'La investigación web está desactivada, así que el modelo no tenía fuentes. Toca la pastilla Local para activarla.';

  @override
  String get noticeNoSourcesNoSearch =>
      'No se hizo ninguna búsqueda para este mensaje, así que el modelo no tenía fuentes. Cambia la pastilla a Web · siempre o pide «busca …».';

  @override
  String noticeStoriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count noticias',
      one: '1 noticia',
    );
    return '$_temp0';
  }

  @override
  String noticeOutletsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count medios',
      one: '1 medio',
    );
    return '$_temp0';
  }

  @override
  String noticeArticlesRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artículos leídos',
      one: '1 artículo leído',
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
  String get noticeLinkUnreadable => 'No se pudo leer la página enlazada.';

  @override
  String get noticeNoWebResults =>
      'Sin resultados web. No se pudo verificar la información actual.';

  @override
  String noticeLinkedRead(int read, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total páginas enlazadas',
      one: '1 página enlazada',
    );
    return '$read de $_temp0 leída(s).';
  }

  @override
  String noticePagesRead(int read, int results, String queries) {
    String _temp0 = intl.Intl.pluralLogic(
      read,
      locale: localeName,
      other: '$read páginas leídas',
      one: '1 página leída',
    );
    return '$_temp0 de $results resultados$queries.';
  }

  @override
  String noticeQueries(int count) {
    return ' ($count consultas)';
  }

  @override
  String get noticeEvidenceNoFit =>
      'Las fuentes web no caben. Aumenta el contexto o reduce la longitud de la respuesta.';

  @override
  String noticeWaitingServer(String client) {
    return 'Esperando a que el servidor del dispositivo termine una solicitud de $client…';
  }

  @override
  String noticeReadingPage(int n, int limit, String host) {
    return 'Leyendo $n de $limit$host…';
  }

  @override
  String noticeToolCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recortes',
      one: '1 recorte',
    );
    return 'Se recortaron resultados de herramientas para que quepan en el contexto ($_temp0). Aumenta el tamaño del contexto o reduce el presupuesto de salida por herramienta.';
  }

  @override
  String noticeDocCut(int percent) {
    return 'El texto adjunto se recortó para que quepa en el contexto (se conservó el $percent %). Aumenta el tamaño del contexto para el archivo completo.';
  }

  @override
  String noticeRefusal(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'le dieron $count fuentes',
      one: 'le dio 1 fuente',
    );
    return 'El modelo dijo que no puede navegar aunque se $_temp0. Regenera o prueba otro modelo.';
  }

  @override
  String noticeNoCitations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'las $count fuentes dadas',
      one: 'la 1 fuente dada',
    );
    return 'La respuesta no cita ninguna de $_temp0; considérala sin verificar.';
  }

  @override
  String noticeBogusCitations(String cited, int count) {
    return 'La respuesta cita la fuente $cited, que no se proporcionó; solo existen [1]–[$count].';
  }

  @override
  String noticeFigures(String figures, String more) {
    return 'No aparece en las fuentes: $figures$more. Considera estas cifras sin verificar.';
  }

  @override
  String noticeFiguresMiscited(String figures, String more) {
    return 'No está en la fuente citada: $figures$more. Otra fuente sí lo da; revisa la cita.';
  }

  @override
  String get noticeCitationsMatched =>
      'El modelo no citó ninguna fuente; las marcas [n] se asociaron a las fuentes por sus palabras y cifras.';

  @override
  String noticeAndMore(int count) {
    return ' y $count más';
  }

  @override
  String get searchChallenge =>
      'DuckDuckGo pidió una verificación antibots, así que la búsqueda automática se pausa un minuto. Los enlaces pegados siguen funcionando.';

  @override
  String searchCooldown(int seconds) {
    return 'La búsqueda está en pausa tras un bloqueo de DuckDuckGo; se reanuda en $seconds s. Los enlaces pegados siguen funcionando.';
  }

  @override
  String get searchRateLimit =>
      'DuckDuckGo está limitando las búsquedas; pausa de un minuto. Los enlaces pegados siguen funcionando.';

  @override
  String get searchMarkup =>
      'DuckDuckGo cambió su página de resultados y no se pudo analizar. Los enlaces pegados siguen funcionando; la búsqueda necesita una actualización de la app.';

  @override
  String get searchUnavailable =>
      'Búsqueda web no disponible (sin conexión o DuckDuckGo inaccesible). No se pudo verificar la información actual.';

  @override
  String noticeThrottle(int drop, String from, String to) {
    return 'La velocidad bajó un $drop % ($from → $to tokens/s). Puede que el teléfono se esté limitando por temperatura; prueba un contexto más corto, menos capas en GPU o un modelo más pequeño.';
  }

  @override
  String get outputGrammarCut =>
      'La salida restringida por la gramática se cortó en el límite de tokens.';

  @override
  String get outputSchemaMismatch =>
      'La salida es JSON válido, pero no el objeto que pide el esquema.';

  @override
  String outputJsonCut(int count) {
    return 'La salida JSON se cortó en el límite de $count tokens y no se puede analizar. Aumenta Tokens máximos.';
  }

  @override
  String get outputNotJson => 'La salida no es JSON válido.';

  @override
  String noticeBatterySaver(String reason, int tokens) {
    return 'Ahorro de batería ($reason): sin razonamiento, respuestas de hasta $tokens tokens, menos páginas leídas.';
  }

  @override
  String saverReasonBattery(int level) {
    return 'batería $level %';
  }

  @override
  String saverReasonHot(String label) {
    return 'teléfono caliente: $label';
  }

  @override
  String newsCollecting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count medios',
      one: '1 medio',
    );
    return 'Reuniendo las noticias de hoy de DuckDuckGo News y $_temp0…';
  }

  @override
  String newsReadingArticles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count artículos',
      one: '1 artículo',
    );
    return 'Leyendo $_temp0…';
  }

  @override
  String get chatErrorNoModel =>
      'Añade un modelo en la pestaña Modelos y luego envía tu mensaje.';

  @override
  String chatErrorSave(String error) {
    return 'No se pudo guardar la respuesta: $error. Copia la respuesta antes de salir de este chat.';
  }

  @override
  String get chatErrorNoText =>
      'El modelo no produjo texto. Prueba otra plantilla u otro modelo.';

  @override
  String chatErrorServing(String model) {
    return 'Este teléfono está sirviendo $model a otro dispositivo. Detén el servidor del dispositivo (Ajustes) para chatear con otro modelo.';
  }

  @override
  String chatErrorServerBusy(String client) {
    return 'El servidor del dispositivo sigue respondiendo a $client. Vuelve a intentarlo cuando termine.';
  }

  @override
  String get settingGroupGeneration => 'Generación';

  @override
  String get settingGroupReasoning => 'Razonamiento';

  @override
  String get settingGroupWeb => 'Investigación web';

  @override
  String get settingGroupTools => 'Herramientas';

  @override
  String get settingGroupOutput => 'Salida estructurada';

  @override
  String get settingGroupContext => 'Contexto';

  @override
  String get settingGroupHardware => 'Hardware';

  @override
  String get settingGroupPrompt => 'Instrucciones';

  @override
  String get settingLabelSystemPrompt => 'Instrucciones personalizadas';

  @override
  String get settingLabelTemperature => 'Temperatura';

  @override
  String get settingLabelTopP => 'Top-P';

  @override
  String get settingLabelMinP => 'Min-P';

  @override
  String get settingLabelTopK => 'Top-K';

  @override
  String get settingLabelTypicalP => 'Typical-P';

  @override
  String get settingLabelRepetitionPenalty => 'Penalización por repetición';

  @override
  String get settingLabelPresencePenalty => 'Penalización por presencia';

  @override
  String get settingLabelFrequencyPenalty => 'Penalización por frecuencia';

  @override
  String get settingLabelRepeatLastN => 'Ventana de penalización (tokens)';

  @override
  String get settingLabelMaxTokens => 'Tokens máximos';

  @override
  String get settingLabelSeed => 'Semilla (0 = aleatoria)';

  @override
  String get settingLabelStopSequences => 'Secuencias de parada';

  @override
  String get settingLabelThinkingModeEnabled => 'Modo de razonamiento';

  @override
  String get settingLabelThinkingBudgetTokens =>
      'Presupuesto de razonamiento (0 = ilimitado)';

  @override
  String get settingLabelWebMode => 'Investigación web';

  @override
  String get settingLabelResearchLoop => 'Investigación guiada por el modelo';

  @override
  String get settingLabelMaxPagesRead => 'Páginas que leer';

  @override
  String get settingLabelEvidencePassages => 'Pasajes que recibe el modelo';

  @override
  String get settingLabelKnowledgeCollection => 'Colección de conocimiento';

  @override
  String get settingLabelToolsEnabled => 'Llamada a herramientas';

  @override
  String get settingLabelToolChoice => 'Uso de herramientas';

  @override
  String get settingLabelToolMaxRounds =>
      'Rondas de herramientas por respuesta';

  @override
  String get settingLabelResponseFormat => 'Formato de respuesta';

  @override
  String get settingLabelJsonSchema => 'Esquema JSON';

  @override
  String get settingLabelGrammar => 'Gramática GBNF';

  @override
  String get settingLabelContextSize => 'Tamaño del contexto';

  @override
  String get settingLabelPromptCache => 'Mantener la conversación en contexto';

  @override
  String get settingLabelBackend => 'Motor de cálculo';

  @override
  String get settingLabelNGpuLayers => 'Capas en GPU';

  @override
  String get settingLabelCpuThreads =>
      'Hilos de CPU (decodificación, 0 = auto)';

  @override
  String get settingLabelBatchThreads => 'Hilos de CPU (precarga, 0 = auto)';

  @override
  String get settingLabelFlashAttention => 'Flash attention';

  @override
  String get settingLabelKvCacheType => 'Tipo de caché K';

  @override
  String get settingLabelVCacheType => 'Tipo de caché V (vacío = igual que K)';

  @override
  String get settingLabelRopeScaling => 'Escalado RoPE';

  @override
  String get settingLabelDraftModelId =>
      'Modelo borrador (decodificación especulativa)';

  @override
  String get hostLocalOnly => 'Solo red local y VPN';

  @override
  String get hostLocalOnlyHint =>
      'Los dispositivos en este Wi-Fi, tu punto de acceso o tu VPN (Tailscale, WireGuard…) pueden conectarse con el token. Se rechazan las solicitudes desde internet.';

  @override
  String settingEmptyMeans(String value) {
    return 'Vacío = $value';
  }

  @override
  String settingEffectiveValue(String value) {
    return 'Valor efectivo: $value';
  }

  @override
  String settingInherit(String value) {
    return 'Heredar ($value)';
  }

  @override
  String get remoteScanQr => 'Escanear código QR';

  @override
  String get remoteScanHint =>
      'Apunta la cámara al código QR del otro teléfono (Ajustes > Usar este dispositivo como servidor).';

  @override
  String get remoteScanInvalid =>
      'Ese código QR no es una conexión de OnDevice LLM. Apunta al código del servidor.';

  @override
  String remoteScanNoCamera(String error) {
    return 'La cámara no está disponible: $error';
  }

  @override
  String get remoteNameConnection => 'Pon nombre a esta conexión';

  @override
  String get remoteNameHint => 'Por ejemplo: PC del salón';

  @override
  String get answerFromMemory =>
      'De la memoria del modelo — puede estar desactualizado.';

  @override
  String get searchTheWeb => 'Buscar en la web';

  @override
  String get searchMissesTitle => 'Preguntas enviadas a la web a mano';

  @override
  String searchMissesHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count preguntas. Cópialas para mejorar las palabras clave de búsqueda; si no, nunca salen de este teléfono.',
      one:
          '1 pregunta. Cópialas para mejorar las palabras clave de búsqueda; si no, nunca salen de este teléfono.',
      zero:
          'Ninguna todavía. Cuando una respuesta venía de la memoria y tocaste Buscar en la web, la pregunta se guarda aquí (solo en este teléfono) para mejorar las palabras clave de búsqueda.',
    );
    return '$_temp0';
  }

  @override
  String get commonCopied => 'Copiado.';

  @override
  String get settingsSearchSection => 'Búsqueda';

  @override
  String searchRegionHint(String region) {
    return 'De dónde vienen las noticias y los resultados de búsqueda. Automático sigue el idioma de la app y el país del teléfono (ahora $region).';
  }

  @override
  String get searchRegionAutomatic => 'Automático';

  @override
  String get researchLoopHint =>
      'Las preguntas que se buscarían las investiga el propio modelo: busca, elige qué páginas leer, vuelve a buscar si hace falta y responde con citas. Los enlaces pegados se siguen leyendo directamente. Más lento por pregunta; compáralo con tus propias preguntas.';

  @override
  String get researchLoopNeedsTools =>
      'Necesita la llamada a herramientas activada con las herramientas web (Ajustes > Herramientas).';

  @override
  String get selectionTitle => '¿Qué hago con el texto seleccionado?';

  @override
  String get selectionExplain => 'Explicarlo';

  @override
  String get selectionSummarize => 'Resumirlo';

  @override
  String get selectionTranslate => 'Traducirlo';

  @override
  String get selectionFix => 'Corregir ortografía y gramática';

  @override
  String get selectionAsk => 'Preguntar sobre ello';

  @override
  String get quickDescribe => 'Describir';

  @override
  String get quickDescribePrompt => 'Describe esta foto con detalle.';

  @override
  String get quickExtractText => 'Extraer texto';

  @override
  String get quickExtractTextPrompt =>
      'Transcribe todo el texto de esta imagen exactamente como está escrito, manteniendo el formato.';

  @override
  String get quickTranslate => 'Traducir';

  @override
  String get quickTranslatePrompt =>
      'Traduce todo el texto de esta imagen al español.';

  @override
  String get quickSolve => 'Resolver';

  @override
  String get quickSolvePrompt =>
      'Resuelve el problema que muestra esta imagen y explica cada paso.';

  @override
  String get quickExplain => 'Explicar';

  @override
  String get quickExplainPrompt =>
      'Explica qué muestra esta imagen y por qué importa.';

  @override
  String get quickIdentify => 'Identificar';

  @override
  String get quickIdentifyPrompt =>
      '¿Qué es esto? Identifícalo y cuéntame lo que sepas.';

  @override
  String get quickSummarise => 'Resumir';

  @override
  String get quickSummarisePrompt =>
      'Resume este documento: la idea principal en una frase y luego los puntos clave.';

  @override
  String get quickKeyPoints => 'Puntos clave';

  @override
  String get quickKeyPointsPrompt =>
      'Enumera los puntos clave de este documento en viñetas breves.';

  @override
  String get quickExplainSimply => 'Explicar fácil';

  @override
  String get quickExplainSimplyPrompt =>
      'Explica este documento con palabras sencillas para alguien nuevo en el tema.';

  @override
  String get quickActionItems => 'Tareas';

  @override
  String get quickActionItemsPrompt =>
      'Enumera cada tarea, plazo y decisión de este documento.';

  @override
  String get quickQuestions => 'Preguntas';

  @override
  String get quickQuestionsPrompt =>
      '¿Qué preguntas debería hacerme sobre este documento antes de fiarme de él?';

  @override
  String get sectionVoice => 'Voz';

  @override
  String get sectionAutomation => 'Atajos y automatización';

  @override
  String get sectionModelConnections => 'Modelo y conexiones';

  @override
  String get sectionAppearanceLanguage => 'Apariencia e idioma';

  @override
  String get sectionData => 'Tus datos';

  @override
  String get advancedNote =>
      'Los valores predeterminados funcionan bien. Estos sirven para ajustar la velocidad, la memoria y la salida.';

  @override
  String get remoteRowOff =>
      'Desactivado · el modelo se ejecuta en este teléfono';

  @override
  String get backupRowHint => 'Guardar o restaurar chats, adjuntos y ajustes';

  @override
  String remoteRowOn(String name) {
    return 'Activado · $name';
  }

  @override
  String get sectionCachePrecision => 'Precisión de la caché';

  @override
  String get sectionCapabilities => 'Capacidades';

  @override
  String get sectionConnections => 'Conexiones';

  @override
  String get sectionEvidence => 'Fuentes para el modelo';

  @override
  String get sectionExtraSamplers => 'Muestreadores adicionales';

  @override
  String get sectionLayers => 'Capas, de la más baja a la más alta';

  @override
  String get sectionPenalties => 'Penalizaciones';

  @override
  String get sectionRope => 'Codificación de posición (RoPE / YaRN)';

  @override
  String get sectionReasoning => 'Razonamiento';

  @override
  String get sectionReproducibility => 'Reproducibilidad';

  @override
  String get sectionSamplerOrder => 'Orden de los muestreadores';

  @override
  String get sectionSpeculative => 'Decodificación especulativa (experimental)';

  @override
  String get sectionTools => 'Herramientas';

  @override
  String get chatSettingsMenu => 'Ajustes de este chat';

  @override
  String chatSettingsMenuCount(int count) {
    return 'Ajustes de este chat · $count';
  }

  @override
  String remoteUsingSummary(String name, String host) {
    return 'Los chats se ejecutan en $name ($host). Los modelos locales no se cargan.';
  }

  @override
  String get remoteNeedsConnection =>
      'Añade una conexión abajo para activarlo.';

  @override
  String get remoteNeedsUrl =>
      'La conexión elegida necesita una dirección http(s) válida.';

  @override
  String get remoteNoUrl => 'sin dirección';

  @override
  String get remoteNoKey => 'sin clave';

  @override
  String get remoteScanShort => 'Escanear QR';

  @override
  String get remotePasteShort => 'Pegar';

  @override
  String get modelProfile => 'Perfil';

  @override
  String modelProfileCount(int count) {
    return 'Perfil · $count';
  }

  @override
  String get modelsFootnote =>
      'Los modelos más grandes responden mejor, pero son más lentos y usan más memoria. La etiqueta de cada modelo indica si cabe en este teléfono.';

  @override
  String get benchmarkRunAgain => 'Repetir';

  @override
  String benchmarkMeasuredAt(String date) {
    return 'Medido el $date';
  }

  @override
  String get unloadShort => 'Liberar';

  @override
  String get unsavedChanges => 'Cambios sin guardar';

  @override
  String get savedNotice => 'Guardado';

  @override
  String get pickerLibrary => 'Biblioteca';

  @override
  String get pickerConnections => 'Conexiones';

  @override
  String get pickerReasoning => 'razonamiento';

  @override
  String get pickerTightRam => 'RAM justa';

  @override
  String get pickerTooLarge => 'demasiado grande para este teléfono';

  @override
  String get pickerNoKey => 'sin clave aún';

  @override
  String get goalPhaseVerifying => 'Comprobando el informe con los hallazgos';

  @override
  String get goalGuardrails => 'Salvaguardas';

  @override
  String get goalSubjectTitle => 'Mantenerse en estos nombres';

  @override
  String get goalSubjectHint =>
      'Encontrados en el objetivo. El modelo debe usarlos tal cual; se descartan las páginas sobre modelos, versiones o generaciones parecidas.';

  @override
  String get goalSubjectNone =>
      'Aún no hay nombres: los productos, personas y lugares del objetivo aparecen aquí al escribir.';

  @override
  String get goalSubjectAdd => 'Añadir un nombre';

  @override
  String get goalSubjectExample => 'p. ej. Sony ZV-E10';

  @override
  String get goalSubjectReset => 'Restablecer';

  @override
  String get goalRulesLabel => 'Reglas propias (opcional)';

  @override
  String get goalRulesHint =>
      'Una por línea, p. ej. Precios en CAD · Solo fuentes de 2026 · Sin rumores';

  @override
  String get goalRulesBuiltIn => 'Reglas que sigue cada objetivo';

  @override
  String get goalRuleSubject =>
      'Usa los nombres tal cual; nunca los cambia por un modelo, versión o generación parecidos.';

  @override
  String get goalRuleEvidence =>
      'Solo afirma lo que dicen las fuentes, cada dato con su cita; nada de memoria.';

  @override
  String get goalRuleOffTopic =>
      'Ignora las fuentes sobre otra cosa y dice qué falta; nunca pide fuentes.';

  @override
  String get goalRuleFigures =>
      'Copia cifras, fechas y precios exactos; da ambas versiones cuando las fuentes no coinciden.';

  @override
  String get goalRuleThinking =>
      'Razona brevemente antes del plan y de la revisión de las pruebas; los pasos y el informe responden directamente, así la búsqueda es más rápida.';

  @override
  String get goalRuleCheck =>
      'Cada paso y el informe se comprueban automáticamente; una comprobación fallida se repite una vez.';

  @override
  String goalCheckDrift(String names) {
    return 'Menciona $names, que no es el tema del objetivo';
  }

  @override
  String goalCheckOffTarget(String names) {
    return 'Investigó $names en su lugar: excluido del informe';
  }

  @override
  String get goalCheckNoSources => 'No se encontraron fuentes';

  @override
  String get goalCheckNoCitations => 'No cita fuentes';

  @override
  String goalCheckBadCitations(String numbers) {
    return 'Cita fuentes que no existen: $numbers';
  }

  @override
  String goalCheckFigures(String figures) {
    return 'Cifras que no están en ninguna fuente: $figures';
  }

  @override
  String goalCheckDroppedFigures(String figures) {
    return 'Cifras retiradas, ausentes de las fuentes: $figures';
  }

  @override
  String get goalCheckAskedUser => 'Pidió información al usuario';

  @override
  String get goalCheckRetried =>
      'Investigado de nuevo tras una comprobación fallida';

  @override
  String get goalCheckRevised =>
      'Reescrito una vez para corregir la comprobación';

  @override
  String get goalReportChecked =>
      'Comprobado: nombres, citas y cifras coinciden con los hallazgos';

  @override
  String get goalStepSearched => 'Búsquedas';

  @override
  String get goalStepTools => 'Llamadas a herramientas';

  @override
  String get goalStepSources => 'Fuentes';

  @override
  String get goalStepReasoning => 'Razonamiento';

  @override
  String goalStepStats(int prompt, int tokens, String seconds, String tps) {
    return '$prompt tokens leídos + $tokens generados · $seconds s · $tps tok/s';
  }

  @override
  String goalStepSearchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count búsquedas',
      one: '1 búsqueda',
    );
    return '$_temp0';
  }

  @override
  String goalStepToolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count llamadas a herramientas',
      one: '1 llamada a herramienta',
    );
    return '$_temp0';
  }

  @override
  String get goalPlanNotes => 'Cómo se hizo el plan';

  @override
  String get goalReviewNotes => 'Razonamiento de la revisión';

  @override
  String get goalCheckLeak =>
      'Se quitó el razonamiento mezclado con la respuesta';

  @override
  String goalSmallModel(String model) {
    return '$model es un modelo pequeño: los objetivos son mucho más precisos con Gemma 4 E2B o un modelo mayor (se mantiene en el tema y cita sus fuentes).';
  }

  @override
  String get goalPartial => 'Resultado parcial — se necesitan más pruebas';

  @override
  String get goalCriteriaReview => 'Criterios de éxito';

  @override
  String goalEvidenceSteps(String steps) {
    return 'Pruebas: pasos $steps';
  }

  @override
  String get backupExportReady =>
      'Copia cifrada enviada al menú de exportación.';

  @override
  String get remoteShareMemory => 'Compartir memoria con esta conexión';

  @override
  String get remoteShareMemoryHint =>
      'Permitir notas seleccionadas en solicitudes a este servidor.';

  @override
  String get remoteLearnMemory => 'Aprender memoria con esta conexión';

  @override
  String get remoteLearnMemoryHint =>
      'Permitir una solicitud aparte al servidor para extraer hechos duraderos de tus mensajes. Los hechos explícitos simples pueden guardarse localmente si la memoria está activada.';

  @override
  String get memoryPin => 'Considerar siempre esta nota';

  @override
  String get memoryUnpin => 'Desfijar nota';

  @override
  String get memoryReconfirm => 'Confirmar que sigue siendo correcto';

  @override
  String get memoryExpire => 'Caducar en 30 días';

  @override
  String get memoryNoExpiry => 'Quitar caducidad';

  @override
  String memoryExpires(String date) {
    return 'Caduca el $date';
  }

  @override
  String get settingsSearch => 'Buscar ajustes';

  @override
  String get settingsFaster => 'Respuestas más rápidas';

  @override
  String get settingsDetailed => 'Más detalle';

  @override
  String get settingsLessMemory => 'Usar menos RAM';

  @override
  String get imageTokenBudget => 'Presupuesto de tokens por foto';

  @override
  String get imageTokenBudgetHint =>
      'Más detalle requiere más memoria y tiempo. Recarga el modelo.';

  @override
  String get documentPreview => 'Vista previa';

  @override
  String get documentEdit => 'Editar';

  @override
  String get documentDraftSaved => 'Borrador guardado en este dispositivo';

  @override
  String get documentVersions => 'Historial de versiones';

  @override
  String get goalQuestionsTitle => 'Unas preguntas primero';

  @override
  String get goalQuestionsHint =>
      'Tus preferencias pueden mejorar el informe. Elige una respuesta, escribe la tuya o salta las preguntas. La investigación espera hasta que continúes.';

  @override
  String get goalYourAnswer => 'Tu respuesta (opcional)';

  @override
  String get goalQuestionsLater => 'Más tarde';

  @override
  String get goalQuestionsSkip => 'Saltar y continuar';

  @override
  String get goalPhaseClarifying => 'Comprobando si hacen falta aclaraciones…';

  @override
  String get goalWaitingAnswers => 'Esperando tus respuestas';

  @override
  String get goalAnswerQuestions => 'Responder preguntas';

  @override
  String get goalClarificationAnswers => 'Tus aclaraciones';

  @override
  String get goalAssumptionsAllowed =>
      'Pregunta omitida — el informe indicará sus supuestos.';

  @override
  String get goalSearchGuidance => 'Orientación de búsquedas e informe';

  @override
  String get goalSearchGuidanceHint =>
      'Explica qué falta, qué preguntas investigar y qué destacar.';

  @override
  String get goalRefineRun => 'Guardar e investigar';

  @override
  String get goalCriteriaSeparate =>
      'Un requisito por línea para medir la cobertura.';

  @override
  String goalCoverage(Object percent, Object target) {
    return 'Requisitos respaldados: $percent% · umbral $target%';
  }

  @override
  String get goalCompletionHint =>
      'Detener cuando esta proporción de requisitos esté respaldada. Las lagunas siguen visibles; se mantienen las citas y verificaciones.';

  @override
  String get goalCompletionTarget => 'Umbral de finalización';

  @override
  String get goalRefine => 'Editar / orientar la investigación';

  @override
  String memoryScanResult(Object count) {
    return 'Se recuperaron $count recuerdos de los chats guardados.';
  }

  @override
  String get memoryScanHistory =>
      'Buscar recuerdos omitidos en los chats guardados';

  @override
  String get goalEvidenceWorkspace => 'Comparar evidencias';

  @override
  String get goalEvidenceSnapshotHint =>
      'Compara los extractos guardados con los hallazgos de cada paso. Son los extractos utilizados por el modelo; la página actual puede haber cambiado. Una fuente o una comprobación automática no demuestra por sí sola una afirmación.';

  @override
  String get goalEvidenceSupported => 'Requisito respaldado';

  @override
  String get goalEvidenceGap => 'Este requisito necesita evidencias';

  @override
  String get goalEvidenceMissing =>
      'No se guardó ningún extracto de esta fuente.';

  @override
  String get goalEvidenceFind => 'Buscar texto en estas fuentes';

  @override
  String get goalEvidencePublished => 'Publicado';

  @override
  String get goalEvidenceRetrieved => 'Recuperado';

  @override
  String get goalEvidenceOpen => 'Abrir página';

  @override
  String get goalEvidenceCopy => 'Copiar extracto';

  @override
  String get goalEvidenceNoMatch =>
      'Sin coincidencias en este extracto guardado.';

  @override
  String get goalEvidenceExcluded =>
      'Este paso se excluyó de las evidencias del informe.';

  @override
  String get contextInspector => 'Inspector de contexto';

  @override
  String get contextSnapshotHint =>
      'Selección de contexto guardada para esta respuesta. Los extractos permiten revisarla; no se usan automáticamente como resúmenes en respuestas futuras.';

  @override
  String get contextSnapshotMissing =>
      'Esta respuesta anterior no tiene una instantánea de contexto guardada.';

  @override
  String get contextTokens => 'Tokens de contexto';

  @override
  String get contextIsolated =>
      'Esta solicitud utilizó la pregunta actual sin los turnos anteriores.';

  @override
  String get contextInstructions => 'Instrucciones proporcionadas al modelo';

  @override
  String get contextCharacters => 'caracteres';

  @override
  String get contextMessages => 'Mensajes de la conversación';

  @override
  String get contextIncluded => 'Incluido';

  @override
  String get contextOmittedIsolated =>
      'Omitido para esta solicitud independiente';

  @override
  String get contextOmittedLimit =>
      'Omitido para respetar el límite de contexto; conservado en el historial';

  @override
  String get contextImages => 'imágenes';

  @override
  String get contextDocuments => 'documentos';

  @override
  String get contextSnippetOnly =>
      'Solo fragmento de búsqueda; no se leyó la página';

  @override
  String get contextStale =>
      'Las evidencias en caché pueden estar desactualizadas';

  @override
  String get goalModelLabel => 'Modelo';

  @override
  String get goalModelNone => 'Ningún modelo local listo';

  @override
  String get goalModelOnStart => 'se carga al iniciar el objetivo';

  @override
  String get contextOmitted => 'Omitido';

  @override
  String get contextEarlierHidden =>
      'Vistas previas de mensajes anteriores no mostradas';

  @override
  String contextCapTrain(String size) {
    return 'Contexto ajustado a $size tokens, el máximo con el que se entrenó este modelo.';
  }

  @override
  String contextCapMemory(String size) {
    return 'Contexto ajustado a $size tokens para que el modelo quepa en la memoria libre.';
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

    return 'No hay suficiente memoria libre para este modelo: necesita unos $needString MB y hay $freeString MB libres. Cierra otras apps o elige un modelo más pequeño.';
  }

  @override
  String contextTrainedFor(String size) {
    return 'El modelo cargado se entrenó para $size tokens.';
  }

  @override
  String contextTrainedForCapped(String size) {
    return 'El modelo cargado se entrenó para $size tokens. Un contexto mayor se reduce a ese tamaño al cargar el modelo, salvo que se configure el escalado de RoPE en Memoria, RoPE y especulación.';
  }

  @override
  String contextTrainedForStretched(String size) {
    return 'El modelo cargado se entrenó para $size tokens; el escalado de RoPE lo amplía más allá y la calidad puede bajar.';
  }

  @override
  String get photosAndVoiceNotes => 'Fotos y notas de voz';

  @override
  String photosAndVoiceNotesBody(Object mb) {
    return 'Encuentra fotos por lo que muestran y grabaciones por lo que dicen, con las mismas preguntas que tus documentos. Funciona en el teléfono; ~$mb MB una sola vez.';
  }

  @override
  String get photosAndVoiceNotesReady =>
      'Las fotos y grabaciones se encuentran por lo que muestran o dicen.';

  @override
  String noticeClaimsNotInSources(String claims, String more) {
    return 'Sin respaldo en las fuentes: $claims$more. Comprueba estas afirmaciones antes de fiarte de ellas.';
  }

  @override
  String noticeClaimsNames(String details) {
    return 'nombres o fechas que ninguna fuente menciona: $details';
  }

  @override
  String get naturalVoiceTitle => 'Voz natural en el dispositivo';

  @override
  String get naturalVoiceHint =>
      'Whisper escucha y Kokoro habla, todo en este teléfono. Usa la voz del sistema mientras no estén descargados.';

  @override
  String get talkOverTitle => 'Hablar encima de la respuesta';

  @override
  String get talkOverHint =>
      'En una conversación, interrumpe hablando. La respuesta suena entonces como una llamada. Desactivado: sonido claro, toca para interrumpir.';

  @override
  String get spokenLengthTitle => 'Longitud de las respuestas habladas';

  @override
  String get spokenLengthHint =>
      'Cuánto de una respuesta dice Conversación en voz alta. Las listas se leen siempre enteras.';

  @override
  String get spokenLengthShort => 'Corta (3 frases)';

  @override
  String get spokenLengthLonger => 'Más larga (6 frases)';

  @override
  String get spokenLengthFull => 'Respuesta entera';

  @override
  String get voiceListeningPack => 'Escucha (Whisper)';

  @override
  String get voiceSpeakingPack => 'Habla (Kokoro)';

  @override
  String get listeningModelTitle => 'Modelo de escucha';

  @override
  String get listeningModelHint =>
      'Parakeet v3 entendió todas las frases de prueba en el teléfono y responde más rápido que Whisper; además entiende mejor el francés y el español. Se descarga aparte y usa más memoria mientras hablas. Parakeet TDT 0.6B v3 de NVIDIA, CC BY 4.0.';

  @override
  String get listeningWhisper => 'Whisper base';

  @override
  String get listeningParakeet => 'Parakeet v3';

  @override
  String get voiceUnpacking => 'Descomprimiendo…';

  @override
  String get voicePick => 'Voz';

  @override
  String get voiceTry => 'Probar';

  @override
  String get voiceSample =>
      '¡Hola! Así sueno cuando leo tus respuestas en voz alta.';

  @override
  String get voiceDownloadBoth => 'Descargar la voz en el dispositivo';

  @override
  String get conversationTitle => 'Conversación';

  @override
  String get convListening => 'Escuchando…';

  @override
  String get convThinking => 'Pensando…';

  @override
  String get convLookingUp => 'Buscando…';

  @override
  String get convSpeaking => 'Hablando · habla para interrumpir';

  @override
  String get convSpeakingTap => 'Hablando · toca para interrumpir';

  @override
  String get convPaused => 'Micrófono apagado';

  @override
  String get convNeedsVoice =>
      'Para una conversación natural y manos libres, descarga la voz en el dispositivo (unos 290 MB). Mientras tanto se usa la voz del sistema.';

  @override
  String convModelMissing(String model) {
    return '$model no está descargado, así que responde otro modelo descargado. Descárgalo en Modelos o elige un modelo con el botón de arriba a la derecha.';
  }

  @override
  String get convNoModel => 'Carga primero un modelo.';

  @override
  String get convModelTitle => 'Modelo de conversación';

  @override
  String get convModelHint =>
      'La conversación responde con Qwen3.5 0.8B en el teléfono: empieza a hablar en pocos segundos. Con una conexión remota activa, su modelo puede responder en su lugar.';

  @override
  String get convModelRemote =>
      'Busca por sí mismo cuando hace falta y recuerda toda la conversación';

  @override
  String convRemoteFailed(String error) {
    return 'La conexión remota no respondió ($error). Respondo en el teléfono.';
  }

  @override
  String get convModelFastest => 'el más rápido';

  @override
  String get convMicDenied =>
      'El micrófono no está permitido. Permítelo en los ajustes del teléfono para hablar.';

  @override
  String get convEnd => 'Terminar la conversación';

  @override
  String get convStopAnswer => 'Detener la respuesta';

  @override
  String get convMute => 'Silenciar el micrófono';

  @override
  String get convUnmute => 'Activar el micrófono';

  @override
  String convLoadingModel(String model) {
    return 'Cargando $model…';
  }

  @override
  String get convHint =>
      'Solo habla. Respondo en voz alta; habla encima para interrumpirme.';

  @override
  String get convInterrupt => 'Interrumpir';

  @override
  String get actionEvent => 'Añadir al calendario';

  @override
  String get actionReminder => 'Añadir recordatorio';

  @override
  String get actionAlarm => 'Poner la alarma';

  @override
  String get actionTimer => 'Iniciar temporizador';

  @override
  String get actionMessage => 'Abrir borrador';

  @override
  String get actionFile => 'Guardar o compartir';

  @override
  String get actionNoApp => 'Ninguna app de este teléfono puede hacerlo.';

  @override
  String get actionConfirmHint =>
      'Preparado para ti: confirmas en la app que se abre.';

  @override
  String get actionConfirmDone => 'He completado esta acción';

  @override
  String actionConfirmedAt(String time) {
    return 'Confirmado a las $time';
  }

  @override
  String get goalAwaitingActions => 'Esperando tu confirmación de la acción';

  @override
  String get actionReadyAnswer =>
      'Listo. Revisa la tarjeta de abajo y toca su botón para terminar.';

  @override
  String get echoedAnswer =>
      'El modelo copió sus instrucciones en lugar de responder, así que no se muestra ninguna respuesta. Abre las fuentes de abajo o pregunta de otra forma.';

  @override
  String get goalActionsTitle => 'Listo para hacer';

  @override
  String get goalSaveReport => 'Guardar el informe';

  @override
  String get goalWatch => 'Vigilar a diario';

  @override
  String goalWatchSet(String time) {
    return 'Seguimiento diario a las $time. Una búsqueda en segundo plano comprueba los cambios y te avisa si hay un resultado nuevo o cambia una cifra. El objetivo completo solo se repite cuando lo pides.';
  }

  @override
  String get goalPreparingActions => 'Preparando acciones…';

  @override
  String get goalPhaseDelivering => 'Preparando lo que pidió el objetivo';

  @override
  String goalNotPrepared(String item, String reason) {
    return 'No preparado: $item ($reason)';
  }

  @override
  String goalDeliverableFile(String format) {
    return 'el archivo $format';
  }

  @override
  String get goalDeliverableEvent => 'el evento del calendario';

  @override
  String get goalDeliverableReminder => 'el recordatorio';

  @override
  String get goalDeliverableAlarm => 'la alarma';

  @override
  String get goalDeliverableTimer => 'el temporizador';

  @override
  String get goalDeliverableMessage => 'el borrador del mensaje';

  @override
  String get goalNotPreparedStopped => 'el objetivo se detuvo';

  @override
  String get goalNotPreparedBudget => 'se agotó el presupuesto del objetivo';

  @override
  String get goalNotPreparedUnreadable =>
      'la respuesta del modelo no se pudo leer';

  @override
  String get goalNotPreparedTooLong =>
      'el informe es demasiado largo para un solo archivo';

  @override
  String get goalNotPreparedNone => 'el modelo no propuso ninguno';

  @override
  String goalNotPreparedInvalid(String problem) {
    return 'la propuesta del modelo estaba incompleta: $problem';
  }

  @override
  String get goalWatchesTitle => 'Objetivos vigilados';

  @override
  String get goalWatchChecking => 'Comprobando…';

  @override
  String get goalWatchWebOff => 'La búsqueda web está desactivada';

  @override
  String get goalWatchNoResults => 'La búsqueda no encontró nada';

  @override
  String get goalWatchOffline => 'No se pudo buscar (¿sin conexión?)';

  @override
  String get goalWatchNotYet => 'Aún sin comprobar';

  @override
  String goalWatchBaseline(String when) {
    return 'Primeros resultados guardados $when';
  }

  @override
  String goalWatchNoChange(String when) {
    return 'Sin cambios · $when';
  }

  @override
  String goalWatchChanged(int fresh, int figures, String when) {
    return '$fresh nuevos, $figures cifras cambiadas · $when';
  }

  @override
  String goalWatchDailyAt(String time) {
    return 'a diario a las $time';
  }

  @override
  String goalWatchNewResult(String title) {
    return 'Nuevo: $title';
  }

  @override
  String get goalWatchCheckNow => 'Comprobar ahora';

  @override
  String get goalWatchRunAgain => 'Repetir el objetivo';

  @override
  String get goalWatchStop => 'Dejar de vigilar';

  @override
  String actionOpenedAt(String time) {
    return 'Abierto a las $time: confírmalo allí';
  }

  @override
  String get remoteServerSettings => 'Usar los ajustes del servidor';

  @override
  String get remoteServerSettingsHint =>
      'La temperatura, el muestreo, la longitud de las respuestas y el contexto vienen del modelo de esta conexión (los valores por defecto de Gemini, los ajustes con los que LM Studio lo cargó…), no de los preajustes del teléfono.';

  @override
  String get sheetAttachments => 'Archivos adjuntos y herramientas';

  @override
  String get sheetNotice => 'Aviso';
}
