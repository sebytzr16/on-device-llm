/// What a component file is to stable-diffusion.cpp.
enum ImageGenRole {
  diffusion,
  vae,
  llm,
  t5xxl,
  embeddingsConnectors,
  audioVae,

  /// ESRGAN weights that upscale a finished picture ×2 (Full HD to 4K).
  upscaler,
}

/// One file of an image or video model. Pinned like chat models: the
/// download is checked against [sizeBytes] and [sha256].
class ImageGenComponent {
  final ImageGenRole role;
  final String fileName;
  final String url;
  final String sha256;
  final int sizeBytes;
  const ImageGenComponent({
    required this.role,
    required this.fileName,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });
}

enum ImageGenKind { image, video }

/// An image or video model: a diffusion transformer, its VAE and its text
/// encoder, plus the settings its model card recommends. Desktop only.
class ImageGenModel {
  final String id;
  final String displayName;
  final String blurb;
  final String license;
  final ImageGenKind kind;
  final List<ImageGenComponent> files;

  /// Recommended defaults; the page lets the user change them.
  final int width, height, steps, frames, fps;
  final double cfgScale;
  final double? flowShift;
  final String sampler;

  /// The fixed schedule a distilled model was trained on, comma-separated;
  /// it overrides [steps].
  final String? sigmas;

  /// Map the weights instead of copying them into RAM, for models larger
  /// than free memory.
  final bool mmap;

  /// Run the text encoder on the CPU. LTX's Gemma 3 encoder returns NaN on
  /// CUDA in stable-diffusion.cpp (white video), so it pays ~2 min on the CPU.
  final bool textEncoderOnCpu;

  /// The Hugging Face repository an imported model came from; null for a
  /// built-in catalog entry.
  final String? sourceRepo;
  final String? sourceRevision;

  const ImageGenModel({
    required this.id,
    required this.displayName,
    required this.blurb,
    required this.license,
    required this.kind,
    required this.files,
    required this.width,
    required this.height,
    required this.steps,
    required this.cfgScale,
    this.sampler = 'euler',
    this.flowShift,
    this.sigmas,
    this.mmap = false,
    this.textEncoderOnCpu = false,
    this.frames = 0,
    this.fps = 0,
    this.sourceRepo,
    this.sourceRevision,
  });

  String get downloadKey => 'image-gen:$id';
  int get sizeBytes => files.fold(0, (a, f) => a + f.sizeBytes);

  /// Added by the user from Hugging Face rather than shipped in the catalog.
  bool get imported => sourceRepo != null;

  ImageGenComponent? file(ImageGenRole role) {
    for (final f in files) {
      if (f.role == role) return f;
    }
    return null;
  }

  /// Auto-fit measures tensors and live device memory, retaining weights on
  /// the compute device first, then RAM/disk as needed. An explicit override
  /// remains available for callers that require host streaming.
  Map<String, Object> loadSettings(
    Map<ImageGenRole, String> paths, {
    bool? offloadToCpu,
  }) => {
    'diffusionModelPath': paths[ImageGenRole.diffusion]!,
    if (paths[ImageGenRole.llm] != null) 'llmPath': paths[ImageGenRole.llm]!,
    if (paths[ImageGenRole.t5xxl] != null)
      't5xxlPath': paths[ImageGenRole.t5xxl]!,
    if (paths[ImageGenRole.embeddingsConnectors] != null)
      'embeddingsConnectorsPath': paths[ImageGenRole.embeddingsConnectors]!,
    if (paths[ImageGenRole.audioVae] != null)
      'audioVaePath': paths[ImageGenRole.audioVae]!,
    if (offloadToCpu != null) 'offloadToCpu': offloadToCpu,
    'flashAttn': true,
    if (mmap) 'mmap': true,
    if (textEncoderOnCpu) 'textEncoderOnCpu': true,
  };

  /// Sampler settings the user does not edit, for each request.
  Map<String, Object> get samplerExtras => {
    'flowShift': ?flowShift,
    'sigmas': ?sigmas,
  };
}

/// How a picture of [width]×[height] is made: the model draws at most
/// 2048 a side in multiples of 32, so a larger picture is drawn at half size
/// and upscaled ×2, and any extra rows or columns are cropped from the
/// middle (Full HD is drawn 1920×1088 and cut to 1080).
({int width, int height, int upscale}) pictureSizePlan(int width, int height) {
  final upscale = width > 2048 || height > 2048 ? 2 : 1;
  int draw(int side) => ((side / upscale) / 32).ceil() * 32;
  return (width: draw(width), height: draw(height), upscale: upscale);
}

/// Sizes offered in one tap. 4K needs the upscaler file.
const picturePresets = [
  (label: 'Square', width: 1024, height: 1024),
  (label: 'Full HD', width: 1920, height: 1080),
  (label: '4K', width: 3840, height: 2160),
];

const _hf = 'https://huggingface.co';
const _qwenImage =
    '$_hf/leejet/Qwen-Image-2.1-GGUF/resolve/cc11433936a06e9765f7c0c0b1f0436cfd2b9856';
const _ltx =
    '$_hf/unsloth/LTX-2.3-GGUF/resolve/96e8ed4925ead3db9ff4d0084f165ef6a74f28d0';
const _ltx25 =
    '$_hf/unsloth/LTX-2.5-GGUF/resolve/ac3c540c6025903784336e99b2dc179385c4c3b7';

/// The VAE, text encoder and upscaler both Qwen-Image quants use.
const _qwenImageShared = [
  ImageGenComponent(
    role: ImageGenRole.vae,
    fileName: 'qwen_image_2.1_vae_bf16.safetensors',
    url:
        '$_hf/Comfy-Org/Qwen-Image-2.1/resolve/main/vae/qwen_image_2.1_vae_bf16.safetensors',
    sha256: 'bb21f7473051e1ac368515dd3f2e15cd44d7a11748ee8823e1ddca3e4876b7c9',
    sizeBytes: 675509688,
  ),
  ImageGenComponent(
    role: ImageGenRole.llm,
    fileName: 'Qwen3VL-8B-Instruct-Q4_K_M.gguf',
    url:
        '$_hf/Qwen/Qwen3-VL-8B-Instruct-GGUF/resolve/main/Qwen3VL-8B-Instruct-Q4_K_M.gguf',
    sha256: '67d1659bfe71b89d50b45a4ad1a9e5b997e5bb16ce5da66a6a6167abd569e9e2',
    sizeBytes: 5027784800,
  ),
  upscalerComponent,
];

/// 4xNomos2_hq_mosr (Phhofm, CC-BY-4.0, MoSR): the upscaler for pictures
/// above 2048 pixels and the default in Upscale mode. Measured 2026-10-27 on
/// a 384 to 768 test: closest to the original of the two (fur, whiskers) and
/// 4x faster than Real-ESRGAN (1.4 s vs 5.6 s); trained on clean pictures.
/// Both models enlarge ×4 and ignore the factor asked; the bridge averages
/// the result down to ×2 when that is what was asked.
const upscalerComponent = ImageGenComponent(
  role: ImageGenRole.upscaler,
  fileName: '4xNomos2_hq_mosr.pth',
  url:
      'https://github.com/Phhofm/models/releases/download/4xNomos2_hq_mosr/4xNomos2_hq_mosr.pth',
  sha256: 'c60dbfc7e6f7d27e03517d1bec3f3cbd16e8cd4288eefd1358952f73f8497ddc',
  sizeBytes: 17213494,
);

/// Upscale mode's models: the user's own pictures. Not in
/// [imageGenCatalog], so they are not offered as generators.
const upscalerTools = [
  ImageGenModel(
    id: 'nomos2-hq-mosr',
    displayName: 'Sharp',
    blurb:
        'Nomos2 MoSR: fine detail like fur, hair and text edges, in a few '
        'seconds. For clean pictures: screenshots, renders, good photos.',
    license: 'CC-BY-4.0',
    kind: ImageGenKind.image,
    files: [upscalerComponent],
    width: 0,
    height: 0,
    steps: 0,
    cfgScale: 0,
  ),
  ImageGenModel(
    id: 'realesrgan-x4plus',
    displayName: 'Clean up',
    blurb:
        'Real-ESRGAN x4plus: removes JPEG blocks, noise and blur while it '
        'upscales. For old, compressed or phone photos; smoother result.',
    license: 'BSD-3-Clause',
    kind: ImageGenKind.image,
    files: [
      // stable-diffusion.cpp cannot run x2plus (pixel-unshuffle input).
      ImageGenComponent(
        role: ImageGenRole.upscaler,
        fileName: 'RealESRGAN_x4plus.pth',
        url:
            'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth',
        sha256:
            '4fa0d38905f75ac06eb49a7951b426670021be3018265fd191d2125df9d682f1',
        sizeBytes: 67040989,
      ),
    ],
    width: 0,
    height: 0,
    steps: 0,
    cfgScale: 0,
  ),
];

/// Largest side Upscale mode takes: the model works at ×4 inside, and an
/// 8192-pixel result is the most RAM and time this desktop should spend.
const upscaleMaxSide = 2048;

/// Files and settings from stable-diffusion.cpp's docs (qwen_image_2.1.md,
/// wan.md, ltx2.md); sizes and hashes from the Hugging Face API, 2026-10-27.
const imageGenCatalog = <ImageGenModel>[
  ImageGenModel(
    id: 'qwen-image-2.1-q8',
    displayName: 'Qwen-Image 2.1',
    blurb:
        'Text to image from Alibaba, good at text inside pictures. 8-bit '
        'weights, the most faithful the app offers. About a minute per '
        'megapixel on an 8 GB GPU; 4K is made in Full HD and upscaled.',
    license: 'Apache-2.0',
    kind: ImageGenKind.image,
    width: 1024,
    height: 1024,
    steps: 20,
    cfgScale: 6,
    files: [
      ImageGenComponent(
        role: ImageGenRole.diffusion,
        fileName: 'qwen_image_2.1-Q8_0.gguf',
        url: '$_qwenImage/qwen_image_2.1-Q8_0.gguf',
        sha256:
            'f8b244b00937f0e444a40dbf7866460871b89b30142594973b6012d1b471dc0a',
        sizeBytes: 7687155744,
      ),
      ..._qwenImageShared,
    ],
  ),
  ImageGenModel(
    id: 'qwen-image-2.1-q4k',
    displayName: 'Qwen-Image 2.1 fast',
    blurb:
        'The same model with 4-bit weights: a 3.5 GB smaller download and '
        'a little quicker, with slightly less detail.',
    license: 'Apache-2.0',
    kind: ImageGenKind.image,
    width: 1024,
    height: 1024,
    steps: 20,
    cfgScale: 6,
    files: [
      ImageGenComponent(
        role: ImageGenRole.diffusion,
        fileName: 'qwen_image_2.1-Q4_K.gguf',
        url: '$_qwenImage/qwen_image_2.1-Q4_K.gguf',
        sha256:
            '29f9c83c249ff0292fb2943fceddfa2319b446601866c82a4f8be062abea72c2',
        sizeBytes: 4197494816,
      ),
      ..._qwenImageShared,
    ],
  ),
  ImageGenModel(
    id: 'wan-2.2-ti2v-5b-q4km',
    displayName: 'Wan 2.2 5B',
    blurb:
        'Text or picture to video from Alibaba: 2 seconds at 16 frames a '
        'second. Several minutes per clip on an 8 GB GPU.',
    license: 'Apache-2.0',
    kind: ImageGenKind.video,
    width: 832,
    height: 480,
    steps: 20,
    cfgScale: 6,
    flowShift: 3,
    frames: 33,
    fps: 16,
    files: [
      ImageGenComponent(
        role: ImageGenRole.diffusion,
        fileName: 'Wan2.2-TI2V-5B-Q4_K_M.gguf',
        url:
            '$_hf/QuantStack/Wan2.2-TI2V-5B-GGUF/resolve/main/Wan2.2-TI2V-5B-Q4_K_M.gguf',
        sha256:
            '95b19697b7f98e65b0a543640e9ca7b4dfec32e2a6e3731e8e10708be52655e2',
        sizeBytes: 3433116000,
      ),
      ImageGenComponent(
        role: ImageGenRole.vae,
        fileName: 'Wan2.2_VAE.safetensors',
        url:
            '$_hf/QuantStack/Wan2.2-TI2V-5B-GGUF/resolve/main/VAE/Wan2.2_VAE.safetensors',
        sha256:
            'e40321bd36b9709991dae2530eb4ac303dd168276980d3e9bc4b6e2b75fed156',
        sizeBytes: 1409400960,
      ),
      ImageGenComponent(
        role: ImageGenRole.t5xxl,
        fileName: 'umt5-xxl-encoder-Q4_K_M.gguf',
        url:
            '$_hf/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q4_K_M.gguf',
        sha256:
            '17cf97a5bbbc60a646d6105b832b6f657ce904a8a1ad970e4b59df0c67584a40',
        sizeBytes: 3655145312,
      ),
    ],
  ),
  ImageGenModel(
    id: 'ltx-2.3-22b-distilled-q4km',
    displayName: 'LTX-2.3 22B',
    blurb:
        'Text or picture to video from Lightricks, the strongest open video '
        'model this app runs. Distilled to 8 steps; needs 32 GB of RAM.',
    license: 'LTX-2 Community License',
    kind: ImageGenKind.video,
    width: 768,
    height: 512,
    steps: 8,
    cfgScale: 1,
    // Lightricks' distilled schedule (ltx-2 pipelines, DISTILLED_SIGMA_VALUES).
    sigmas: '1.0,0.99375,0.9875,0.98125,0.975,0.909375,0.725,0.421875,0.0',
    mmap: true,
    frames: 49,
    fps: 24,
    files: [
      ImageGenComponent(
        role: ImageGenRole.diffusion,
        fileName: 'ltx-2.3-22b-distilled-1.1-Q4_K_M.gguf',
        url: '$_ltx/distilled-1.1/ltx-2.3-22b-distilled-1.1-Q4_K_M.gguf',
        sha256:
            '5d09efdc0b8ec2054c44a05366cd7c6634ffa333b379b1f8baf018a78974b73d',
        sizeBytes: 14194441248,
      ),
      ImageGenComponent(
        role: ImageGenRole.vae,
        fileName: 'ltx-2.3-22b-distilled_video_vae.safetensors',
        url: '$_ltx/vae/ltx-2.3-22b-distilled_video_vae.safetensors',
        sha256:
            'e68d6d8f8a42942ac9b862cc315beb3bc30805a8876c7ad63ba5bf7a2b8e168a',
        sizeBytes: 1452256522,
      ),
      ImageGenComponent(
        role: ImageGenRole.audioVae,
        fileName: 'ltx-2.3-22b-distilled_audio_vae.safetensors',
        url: '$_ltx/vae/ltx-2.3-22b-distilled_audio_vae.safetensors',
        sha256:
            '3cd6a6eb8cb28f5ecc12f1f3126952b2a3d2b0b42ad3270e63cefafafe0d9b57',
        sizeBytes: 364853140,
      ),
      ImageGenComponent(
        role: ImageGenRole.embeddingsConnectors,
        fileName: 'ltx-2.3-22b-distilled_embeddings_connectors.safetensors',
        url:
            '$_ltx/text_encoders/ltx-2.3-22b-distilled_embeddings_connectors.safetensors',
        sha256:
            'c61cbb396e2a8175d8b2da51f0fdac885a4ccd22c9f64dafa5aa2c455dc8a507',
        sizeBytes: 2312144712,
      ),
      ImageGenComponent(
        role: ImageGenRole.llm,
        fileName: 'gemma-3-12b-it-qat-Q4_0.gguf',
        url:
            '$_hf/unsloth/gemma-3-12b-it-qat-GGUF/resolve/858acec7ec0541a46c39985c95d3b52d8f3ab183/gemma-3-12b-it-qat-Q4_0.gguf',
        sha256:
            'a6e5c91ed89bcfba3677c33706bc195ca5784c3bc35736bef78d23bb612d1fe8',
        sizeBytes: 6909282688,
      ),
    ],
  ),
  // LTX-2.5 (stable-diffusion.cpp docs/ltx2.md): same transformer family,
  // Gemma 4 12B text encoder with the projection built in (no connectors
  // file), and the conv video VAE (the default one is a diffusion decoder
  // sd.cpp does not run). Sizes and hashes from the Hugging Face API,
  // 2026-11-13.
  ImageGenModel(
    id: 'ltx-2.5-22b-distilled-q4km',
    displayName: 'LTX-2.5 22B',
    blurb:
        'Text or picture to video from Lightricks, newer than LTX-2.3. '
        'Distilled to 8 steps; needs 32 GB of RAM and a 26 GB text encoder.',
    license: 'LTX-2 Community License',
    kind: ImageGenKind.video,
    width: 768,
    height: 512,
    steps: 8,
    cfgScale: 1,
    sigmas: '1.0,0.99375,0.9875,0.98125,0.975,0.909375,0.725,0.421875,0.0',
    mmap: true,
    textEncoderOnCpu: true,
    frames: 49,
    fps: 24,
    files: [
      ImageGenComponent(
        role: ImageGenRole.diffusion,
        fileName: 'ltx-2.5-22b-distilled-Q4_K_M.gguf',
        url: '$_ltx25/distilled/ltx-2.5-22b-distilled-Q4_K_M.gguf',
        sha256:
            'ba40d53770314e69e88361661e55c6cc3b12a363646ba2ea53c8bcd459b66747',
        sizeBytes: 13584703872,
      ),
      ImageGenComponent(
        role: ImageGenRole.vae,
        fileName: 'ltx-2.5-video-vae-conv-bf16.safetensors',
        url: '$_ltx25/vae/ltx-2.5-video-vae-conv-bf16.safetensors',
        sha256:
            '685b06ee3d9b2039647698fc4ea33175112462fc374e2777312c907897dfce8d',
        sizeBytes: 1452269922,
      ),
      ImageGenComponent(
        role: ImageGenRole.audioVae,
        fileName: 'ltx-2.5-audio-vae-bf16.safetensors',
        url: '$_ltx25/vae/ltx-2.5-audio-vae-bf16.safetensors',
        sha256:
            'c52733d37f6a7fb7949c3dc0fb468c6cb2169e4d836983a73babb9f0d54837a5',
        sizeBytes: 364866540,
      ),
      ImageGenComponent(
        role: ImageGenRole.llm,
        fileName: 'gemma4-12b-with-proj-ltx-2.5-bf16.safetensors',
        url:
            '$_ltx25/text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors',
        sha256:
            'ef7243612fdae7a75cb4d5cee9433e81380675fb6c213bd98ae74a9cd16561d1',
        sizeBytes: 26263858182,
      ),
    ],
  ),
];

/// Create's first model when the user has not picked one (owner
/// 2026-11-12: the fastest image model that fits). Speed follows the
/// diffusion weights' size on any card, since smaller weights both stay on
/// the graphics card more often and do less work per step; so it is the
/// picture model with the smallest diffusion file, among downloaded ones
/// when any are, else among all of [models].
/// The catalog picture model and video model to recommend for a graphics
/// card with [vramMb] of memory (owner 2026-11-12: one of each per GPU):
/// of each kind, the one with the largest diffusion weights that stay on
/// the card with 2 GB to spare for the text encoder's turn and compute
/// buffers, else the smallest. Imported models are never recommended;
/// nothing is when the card's memory is unknown.
Set<String> recommendedImageGenModels(double vramMb) {
  if (vramMb <= 0) return const {};
  int weights(ImageGenModel m) =>
      m.file(ImageGenRole.diffusion)?.sizeBytes ?? m.sizeBytes;
  final picks = <String>{};
  for (final kind in ImageGenKind.values) {
    final all = imageGenCatalog.where((m) => m.kind == kind).toList();
    if (all.isEmpty) continue;
    final fit = all
        .where((m) => weights(m) / 1048576 + 2048 <= vramMb)
        .toList();
    picks.add(
      (fit.isEmpty
              ? all.reduce((a, b) => weights(b) < weights(a) ? b : a)
              : fit.reduce((a, b) => weights(b) > weights(a) ? b : a))
          .id,
    );
  }
  return picks;
}

ImageGenModel defaultImageGenModel(
  List<ImageGenModel> models, {
  Set<String> downloaded = const {},
}) {
  final pictures = models.where((m) => m.kind == ImageGenKind.image).toList();
  if (pictures.isEmpty) return models.first;
  final ready = pictures.where((m) => downloaded.contains(m.id)).toList();
  final pool = ready.isEmpty ? pictures : ready;
  int weights(ImageGenModel m) =>
      m.file(ImageGenRole.diffusion)?.sizeBytes ?? m.sizeBytes;
  return pool.reduce((a, b) => weights(b) < weights(a) ? b : a);
}
