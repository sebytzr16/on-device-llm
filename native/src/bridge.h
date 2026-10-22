#pragma once
#include <stdint.h>
#if defined(_WIN32)
#define OD_API __declspec(dllexport)
#else
#define OD_API __attribute__((visibility("default"))) __attribute__((used))
#endif
#ifdef __cplusplus
extern "C" {
#endif
OD_API int32_t od_version(void);
// options: JSON, e.g. {"cacheDir": "/data/user/0/<pkg>/cache", "owner": 3}.
// Backends that compile kernels (OpenCL) persist them under cacheDir; empty
// disables the cache. owner tags the runtime with the window that made it.
OD_API void * od_create(const char * options);
OD_API void od_destroy(void * handle);
// Frees the models of every runtime created with that owner and refuses
// further work on them: an Android window closed while the process lives
// on. Callable from any thread; returns how many models were freed.
OD_API int32_t od_release_owner(int64_t owner);
// Thread-safe cancellation by stable session id; stale ids are harmless.
// These additive ABI 6 exports never access a runtime from the calling thread.
OD_API int64_t od_session_id(void * handle);
OD_API void od_cancel_session(int64_t session);
OD_API void od_reset_cancel(void * handle);
OD_API int32_t od_cancelled(void * handle);
OD_API const char * od_error(void * handle);
OD_API const char * od_info(void * handle);
// JSON prompt budget without trimming history or changing generation state.
OD_API const char * od_preview(void * handle, const char * request);
// settings (JSON): context/threads/backend as before, plus (ABI 6)
//   kvCacheType / vCacheType, ropeScaling + rope/yarn numbers,
//   loraAdapters: [{path, scale}], draftModel + draftMaxTokens (speculative).
// The context is capped to the model's trained length and to free memory
// (memoryGuard: false turns that off); od_info's effectiveSettings reports
// contextRequested and contextCap ("", "train" or "memory").
OD_API int32_t od_load(void * handle, const char * path, const char * settings);
// request (JSON): messages (role/content, optional images, tool_calls,
// tool_call_id), settings (sampling, stop sequences, seed, response format),
// tools: [{name, description, parameters}] for native tool calling.
OD_API int32_t od_begin(void * handle, const char * request);
// 0 = prefill progress, 1 = token bytes, 2 = end, -1 = error. A step may
// emit several tokens at once (speculative decoding) or none (a stop
// sequence prefix is being held back).
OD_API int32_t od_step(void * handle, uint8_t * output, int32_t capacity, int32_t * length);
// Embedding models (loaded with settings {"embedding": true}): request
// {"texts": [...]} -> {"dim": n, "vectors": [[...], ...]}, L2-normalised.
OD_API const char * od_embed(void * handle, const char * request);
// Reads GGUF metadata of a LoRA adapter without loading a model:
// {"architecture", "type", "name", "keys": {...}} or null (see od_error).
OD_API const char * od_adapter_info(void * handle, const char * path);
#ifdef __cplusplus
}
#endif
