#pragma once
#include <stdint.h>

#if defined(_WIN32)
#define OD_SD_API __declspec(dllexport)
#else
#define OD_SD_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct od_sd_ctx_t od_sd_ctx_t;

OD_SD_API od_sd_ctx_t* od_sd_create(const char* options);
OD_SD_API void         od_sd_destroy(od_sd_ctx_t* ctx);

OD_SD_API int32_t od_sd_load(od_sd_ctx_t* ctx,
    const char* model_path,
    const char* vae_path,
    const char* clip_l_path,
    const char* settings);

OD_SD_API const char* od_sd_error(od_sd_ctx_t* ctx);

typedef void (*od_sd_progress_fn)(int32_t step, int32_t total, void* user_data);

OD_SD_API uint8_t* od_sd_txt2img(od_sd_ctx_t* ctx,
    const char* request,
    od_sd_progress_fn progress_cb,
    void* user_data,
    int32_t* out_width,
    int32_t* out_height);

OD_SD_API uint8_t* od_sd_img2img(od_sd_ctx_t* ctx,
    const char* request,
    const uint8_t* init_image,
    int32_t init_width,
    int32_t init_height,
    od_sd_progress_fn progress_cb,
    void* user_data,
    int32_t* out_width,
    int32_t* out_height);

// Version 2: video. Returns every frame as packed RGBA, one after another,
// freed with od_sd_free_image. init_image (RGBA) is optional.
OD_SD_API uint8_t* od_sd_txt2vid(od_sd_ctx_t* ctx,
    const char* request,
    const uint8_t* init_image,
    int32_t init_width,
    int32_t init_height,
    od_sd_progress_fn progress_cb,
    void* user_data,
    int32_t* out_width,
    int32_t* out_height,
    int32_t* out_frames,
    int32_t* out_fps);

// Writes od_sd_txt2vid frames to an MJPG .avi file. Returns 1 on success.
OD_SD_API int32_t od_sd_save_video(const char* path, const uint8_t* rgba,
    int32_t width, int32_t height, int32_t frames, int32_t fps);

// Version 3: enlarges an RGBA picture with an ESRGAN model (.pth or
// .safetensors), e.g. Full HD to 4K. factor is 2 or the model's own scale.
// Freed with od_sd_free_image; errors land in od_sd_error(ctx).
OD_SD_API uint8_t* od_sd_upscale(od_sd_ctx_t* ctx,
    const char* model_path,
    const uint8_t* rgba,
    int32_t width,
    int32_t height,
    int32_t factor,
    int32_t* out_width,
    int32_t* out_height);

OD_SD_API void    od_sd_free_image(uint8_t* image);
OD_SD_API void    od_sd_reset_cancel(od_sd_ctx_t* ctx);
OD_SD_API void    od_sd_cancel(od_sd_ctx_t* ctx);
OD_SD_API int32_t od_sd_version(void);

#ifdef __cplusplus
}
#endif
