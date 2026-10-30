"""Offline CPU bridge check: pass a bridge DLL and a local GGUF path."""
import ctypes
import json
import sys

api = ctypes.CDLL(sys.argv[1])
api.od_create.argtypes = [ctypes.c_char_p]
api.od_create.restype = ctypes.c_void_p
for name in ('od_error', 'od_info'):
    fn = getattr(api, name)
    fn.argtypes = [ctypes.c_void_p]
    fn.restype = ctypes.c_char_p
api.od_load.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
api.od_load.restype = ctypes.c_int32
api.od_preview.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
api.od_preview.restype = ctypes.c_char_p
api.od_destroy.argtypes = [ctypes.c_void_p]
handle = api.od_create(b'{}')
settings = dict(backend='cpu', nGpuLayers=0, contextSize=2048,
                effectiveThreads=4, memoryGuard=False)
request = json.dumps(dict(messages=[dict(role='user', content='Hello')],
                          settings=dict(maxTokens=16))).encode()

def load(template):
    settings['chatTemplate'] = template
    return api.od_load(handle, sys.argv[2].encode(), json.dumps(settings).encode())

def preview():
    result = api.od_preview(handle, request)
    assert result, api.od_error(handle)
    return json.loads(result)['formattedPrompt']

try:
    assert load('') == 0, api.od_error(handle)
    original = preview()
    embedded = json.loads(api.od_info(handle))['embeddedChatTemplate']
    assert embedded
    custom = "CUSTOM_TEMPLATE_MARKER:{% for m in messages %}{{ m['role'] }}={{ m['content'] }};{% endfor %}assistant="
    assert load(custom) == 0, api.od_error(handle)
    changed = preview()
    assert changed != original and 'CUSTOM_TEMPLATE_MARKER:user=Hello;' in changed
    assert json.loads(api.od_info(handle))['embeddedChatTemplate'] == embedded
    print('PASS: custom Jinja changes formatted prompt; embedded template preserved.')
    assert load('') == 0, api.od_error(handle)
    assert preview() == original
    assert json.loads(api.od_info(handle))['abiVersion'] == 7
    print('PASS: reset restores the embedded prompt; ABI remains 7.')
    assert load('{% for m in messages %}') != 0
    error = api.od_error(handle).decode()
    assert 'Invalid prompt template:' in error and len(error) > len('Invalid prompt template: ')
    print('PASS: broken Jinja fails load with parser message:', error)
finally:
    api.od_destroy(handle)
