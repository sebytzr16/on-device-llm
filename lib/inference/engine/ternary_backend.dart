// Bonsai 2 (PrismML) ternary models. Their weights use the GGML types
// PQ2_0 = 142 and PTQ1_0 = 143, added by native/patches/bonsai-ternary.patch.
// Only that patch's CPU and CUDA kernels implement them: a GPU backend
// without kernels dequantizes every ternary tensor on the CPU first, which
// measured 0.06 tok/s on Vulkan against 27 tok/s on the CPU and 270 on CUDA
// (owner report, 2026-11-13).

/// GGUF `general.file_type` values PrismML writes for ternary weights: 141 is
/// their published PQ2_0 metadata, 142 the legacy PQ2_0 value and 143 PTQ1_0.
const _ternaryFileTypes = {141, 142, 143};

/// Bonsai 2 catalog ids are ternary ("bonsai2-9b-q2_0",
/// "bonsai2-27b-ptq1_0").
const _ternaryCatalogPrefix = 'bonsai2-';

/// Backends whose bridge has no PQ2_0/PTQ1_0 kernels, so a ternary model
/// loaded there crawls. Add one here only when the native patch grows
/// kernels for it; CUDA and the CPU do have them.
const _noTernaryKernels = {'vulkan', 'opencl', 'metal', 'qnn'};

/// Whether a [ternary] model has to run on the processor with [backend]
/// instead of its graphics card. Callers resolve `auto` to the backend it
/// picked first: leaving it out keeps a CUDA load on CUDA.
bool ternaryNeedsCpu({required String backend, required bool ternary}) =>
    ternary && _noTernaryKernels.contains(backend.trim().toLowerCase());

/// Whether this is a Bonsai 2 ternary model, from its [catalogId] or, when
/// the GGUF header was already read, its `general.fileType`.
bool isTernaryModel({String? catalogId, int? fileType}) {
  if (catalogId != null && catalogId.startsWith(_ternaryCatalogPrefix)) {
    return true;
  }
  return fileType != null && _ternaryFileTypes.contains(fileType);
}
