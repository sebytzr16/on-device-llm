import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Announces the local server on the LAN through Windows' own DNS-SD
/// responder (dnsapi, Windows 10 1809+), under the type the Android app
/// browses for. Only the endpoint is shared, as on the phone.
class WindowsMdns {
  static const _version1 = 1;
  static const _pending = 9506; // DNS_REQUEST_PENDING

  static DynamicLibrary? _dns;
  static NativeCallable<_CompleteNative>? _complete;
  static _Registration? _active;
  static final _registrations = <int, _Registration>{};
  static final _strings = <Pointer<Utf16>>[];

  static DynamicLibrary get _lib => _dns ??= DynamicLibrary.open('dnsapi.dll');

  static bool get available {
    if (!Platform.isWindows) return false;
    try {
      return _lib.providesSymbol('DnsServiceRegister');
    } catch (_) {
      return false;
    }
  }

  /// [address] is the IPv4 the phone should connect to; the name shown on
  /// the phone is [name].
  static Future<void> advertise({
    required String name,
    required String address,
    required int port,
  }) async {
    await stop();
    final ip = InternetAddress.tryParse(address);
    if (ip == null || ip.type != InternetAddressType.IPv4) {
      throw ArgumentError.value(address, 'address', 'Not an IPv4 address');
    }
    final construct = _lib.lookupFunction<_ConstructNative, _ConstructDart>(
      'DnsServiceConstructInstance',
    );
    final register = _lib.lookupFunction<_RegisterNative, _RegisterDart>(
      'DnsServiceRegister',
    );
    _complete ??= NativeCallable<_CompleteNative>.listener(_onComplete);
    final ip4 = calloc<Uint32>();
    final b = ip.rawAddress;
    // IP4_ADDRESS is in network byte order.
    ip4.value = b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24;
    final instance = construct(
      _wide('${_label(name)}._odllm._tcp.local'),
      _wide('${_label(Platform.localHostname)}.local'),
      ip4,
      nullptr,
      port,
      0,
      0,
      0,
      nullptr,
      nullptr,
    );
    // The instance holds its own copies.
    calloc.free(ip4);
    _freeStrings();
    if (instance == nullptr) {
      throw StateError('Windows could not build the service record.');
    }
    final request = calloc<_RegisterRequest>()
      ..ref.version = _version1
      ..ref.interfaceIndex = 0
      ..ref.instance = instance
      ..ref.callback = _complete!.nativeFunction
      ..ref.context = nullptr
      ..ref.credentials = nullptr
      ..ref.unicastEnabled = 0;
    request.ref.context = request.cast();
    final state = _Registration(request);
    _registrations[request.address] = state;
    final status = register(request, nullptr);
    if (status != _pending) {
      _release(state);
      throw StateError('Windows refused the service record ($status).');
    }
    _active = state;
  }

  static Future<void> stop() async {
    final state = _active;
    if (state == null) return;
    _active = null;
    state.stopping = true;
    if (!state.registering) _deregister(state);
    await state.done.future;
  }

  static void _deregister(_Registration state) {
    try {
      final status = _lib.lookupFunction<_RegisterNative, _RegisterDart>(
        'DnsServiceDeRegister',
      )(state.request, nullptr);
      if (status != _pending) _release(state);
    } catch (_) {
      _release(state);
    }
  }

  static void _onComplete(
    int status,
    Pointer<Void> context,
    Pointer<Void> instance,
  ) {
    final state = _registrations[context.address];
    if (state == null) return;
    final original = state.request.ref.instance;
    if (state.registering && status == 0) {
      // Windows returns the registered record. Keep that one for deregister,
      // releasing the constructed input when it is a separate allocation.
      if (instance != nullptr && instance != original) {
        _freeInstance(original);
        state.request.ref.instance = instance;
      }
      state.registering = false;
      if (state.stopping) _deregister(state);
      return;
    }
    if (instance != nullptr && instance != original) _freeInstance(instance);
    _release(state);
  }

  static void _release(_Registration state) {
    if (_registrations.remove(state.request.address) == null) return;
    if (identical(_active, state)) _active = null;
    _freeInstance(state.request.ref.instance);
    calloc.free(state.request);
    state.done.complete();
  }

  static void _freeInstance(Pointer<Void> instance) {
    try {
      _lib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('DnsServiceFreeInstance')(instance);
    } catch (_) {}
  }

  /// One DNS label: no dots, at most 63 bytes.
  static String _label(String text) {
    final clean = text.replaceAll('.', ' ').trim();
    return clean.length > 60 ? clean.substring(0, 60) : clean;
  }

  static Pointer<Utf16> _wide(String text) {
    final p = text.toNativeUtf16();
    _strings.add(p);
    return p;
  }

  static void _freeStrings() {
    for (final p in _strings) {
      calloc.free(p);
    }
    _strings.clear();
  }
}

class _Registration {
  final Pointer<_RegisterRequest> request;
  final done = Completer<void>();
  bool registering = true, stopping = false;
  _Registration(this.request);
}

final class _RegisterRequest extends Struct {
  @Uint32()
  external int version;
  @Uint32()
  external int interfaceIndex;
  external Pointer<Void> instance;
  external Pointer<NativeFunction<_CompleteNative>> callback;
  external Pointer<Void> context;
  external Pointer<Void> credentials;
  @Int32()
  external int unicastEnabled;
}

typedef _CompleteNative =
    Void Function(Uint32 status, Pointer<Void> context, Pointer<Void> instance);
typedef _ConstructNative =
    Pointer<Void> Function(
      Pointer<Utf16> service,
      Pointer<Utf16> host,
      Pointer<Uint32> ip4,
      Pointer<Void> ip6,
      Uint16 port,
      Uint16 priority,
      Uint16 weight,
      Uint32 count,
      Pointer<Pointer<Utf16>> keys,
      Pointer<Pointer<Utf16>> values,
    );
typedef _ConstructDart =
    Pointer<Void> Function(
      Pointer<Utf16> service,
      Pointer<Utf16> host,
      Pointer<Uint32> ip4,
      Pointer<Void> ip6,
      int port,
      int priority,
      int weight,
      int count,
      Pointer<Pointer<Utf16>> keys,
      Pointer<Pointer<Utf16>> values,
    );
typedef _RegisterNative =
    Uint32 Function(Pointer<_RegisterRequest> request, Pointer<Void> cancel);
typedef _RegisterDart =
    int Function(Pointer<_RegisterRequest> request, Pointer<Void> cancel);
