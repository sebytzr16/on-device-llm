"""Offline smoke regression: python native/tests/sd_load_cancel_test.py <DLL>."""
import ctypes
import os
import sys
from pathlib import Path

path = Path(sys.argv[1]).resolve()
with os.add_dll_directory(str(path.parent)):
    bridge = ctypes.CDLL(str(path))
bridge.od_sd_create.argtypes = [ctypes.c_char_p]
bridge.od_sd_create.restype = ctypes.c_void_p
for name in ["od_sd_cancel", "od_sd_reset_cancel", "od_sd_destroy"]:
    getattr(bridge, name).argtypes = [ctypes.c_void_p]
bridge.od_sd_load.argtypes = [ctypes.c_void_p] + [ctypes.c_char_p] * 4
bridge.od_sd_error.argtypes = [ctypes.c_void_p]
bridge.od_sd_error.restype = ctypes.c_char_p
ctx = bridge.od_sd_create(b"{}")
try:
    # A Stop delivered before the worker enters od_sd_load must survive entry.
    bridge.od_sd_cancel(ctx)
    assert bridge.od_sd_load(ctx, b"missing.gguf", b"", b"", b"{}") == 0
    assert bridge.od_sd_error(ctx) == b"Loading cancelled", bridge.od_sd_error(ctx)
    # Admission of the next job resets the flag and reaches input validation.
    bridge.od_sd_reset_cancel(ctx)
    assert bridge.od_sd_load(ctx, b"", b"", b"", b"{}") == 0
    assert bridge.od_sd_error(ctx) == b"model_path or diffusionModelPath is required"
finally:
    bridge.od_sd_destroy(ctx)
print("SD load cancellation: all tests passed")
