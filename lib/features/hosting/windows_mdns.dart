import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

/// Announces the local server on the LAN through Windows' own DNS-SD
/// responder (dnsapi, Windows 10 1809+), under the type the Android app
/// browses for. Only the endpoint is shared, as on the phone.
class WindowsMdns {
  static const _version1 = 1;
  static const _pending = 9506; // DNS_REQUEST_PENDING

  static DynamicLibrary? _dns;
  static NativeCallable<_CompleteNative>? _complete;
  static _Registration? _active;
  static Future<void> _operations = Future.value();
  static final _registrations = <int, _Registration>{};
  static final _strings = <Pointer<Utf16>>[];

  /// Records Windows has not released yet. Each one keeps its native request
  /// and instance allocated until the responder calls back, so restarts must
  /// not allocate without bound (audit 06a2-1).
  static int maxPending = 4;

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
    bool Function()? isCurrent,
  }) => _replace(() => _advertise(name, address, port), isCurrent: isCurrent);

  static Future<void> _serialize(Future<void> Function() action) {
    final next = _operations.then((_) => action());
    _operations = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  static Future<void> _replace(
    void Function() advertise, {
    bool Function()? isCurrent,
  }) => _serialize(() async {
    if (isCurrent?.call() == false) return;
    await _stop();
    if (isCurrent?.call() == false) return;
    if (_registrations.length >= maxPending) {
      // Reusing a request Windows may still read would corrupt it; refusing
      // keeps the leak bounded instead.
      throw StateError('Windows has not released an earlier service record.');
    }
    advertise();
  });

  static void _advertise(String name, String address, int port) {
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
    _register(
      instance,
      register,
      (request) => _lib.lookupFunction<_RegisterNative, _RegisterDart>(
        'DnsServiceDeRegister',
      )(request, nullptr),
      _cancel,
      _freeInstance,
    );
  }

  static void _register(
    Pointer<Void> instance,
    _RegisterDart register,
    int Function(Pointer<_RegisterRequest>) deregister,
    void Function(Pointer<_ServiceCancel>) cancelRegistration,
    void Function(Pointer<Void>) freeInstance,
  ) {
    final cancel = calloc<_ServiceCancel>();
    final request = calloc<_RegisterRequest>()
      ..ref.version = _version1
      ..ref.interfaceIndex = 0
      ..ref.instance = instance
      ..ref.callback = _callback
      ..ref.context = nullptr
      ..ref.credentials = nullptr
      ..ref.unicastEnabled = 0;
    request.ref.context = request.cast();
    final state = _Registration(
      request,
      cancel,
      deregister,
      cancelRegistration,
      freeInstance,
    );
    _registrations[request.address] = state;
    try {
      final status = register(request, cancel.cast<Void>());
      if (status != _pending) {
        throw StateError('Windows refused the service record ($status).');
      }
    } catch (_) {
      _release(state);
      rethrow;
    }
    _active = state;
  }

  static Future<void> stop() => _serialize(_stop);

  static Future<void> _stop() async {
    final state = _active;
    if (state == null) return;
    _active = null;
    state.stopping = true;
    if (!state.registering) _deregister(state);
    if (await awaitRelease(state.done.future, stopTimeout)) return;
    // Deregistration has no cancellation handle. Keep its request alive.
    if (state.registering) state.cancelRegistration(state.cancelPointer);
  }

  /// How long [stop] waits for Windows to confirm it gave the record back.
  static Duration stopTimeout = const Duration(seconds: 2);

  /// Waits for [done] at most [limit]; false means it never completed.
  static Future<bool> awaitRelease(Future<void> done, Duration limit) async {
    try {
      await done.timeout(limit);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  /// Drives native operation results without registering a LAN record.
  @visibleForTesting
  static Future<void> debugAdvertise({
    required int Function(void Function(int)) register,
    required int Function(void Function(int)) deregister,
    required void Function() cancel,
    bool Function()? isCurrent,
  }) => _replace(() {
    _register(
      calloc<Uint8>().cast(),
      (request, _) =>
          register((status) => _onComplete(status, request.cast(), nullptr)),
      (request) =>
          deregister((status) => _onComplete(status, request.cast(), nullptr)),
      (_) => cancel(),
      calloc.free,
    );
  }, isCurrent: isCurrent);

  @visibleForTesting
  static bool get debugHasCallback => _complete != null;

  static Pointer<NativeFunction<_CompleteNative>> get _callback =>
      (_complete ??= NativeCallable<_CompleteNative>.listener(
        _onComplete,
      )).nativeFunction;

  static void _closeIdleCallback() {
    if (_registrations.values.any(
      (state) => state.registering || state.deregistering,
    )) {
      return;
    }
    _complete?.close();
    _complete = null;
  }

  static void _deregister(_Registration state) {
    while (state.deregisterAttempts < 2) {
      state.deregisterAttempts++;
      state.request.ref.callback = _callback;
      state.deregistering = true;
      try {
        if (state.deregister(state.request) == _pending) return;
      } catch (e, st) {
        quietFailure('windows_mdns deregister', e, st);
      }
      state.deregistering = false;
    }
    // Windows refused twice: it never took ownership of the request, so the
    // record is released instead of being kept (and blocking later
    // advertisements) for the rest of the process.
    _release(state);
  }

  /// Asks Windows to cancel a registration that never completed.
  static void _cancel(Pointer<_ServiceCancel> cancel) {
    try {
      _lib.lookupFunction<
        Uint32 Function(Pointer<_ServiceCancel>),
        int Function(Pointer<_ServiceCancel>)
      >('DnsServiceRegisterCancel')(cancel);
    } catch (e, st) {
      quietFailure('windows_mdns:146', e, st);
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
        state.freeInstance(original);
        state.request.ref.instance = instance;
      }
      state.registering = false;
      if (state.stopping) _deregister(state);
      _closeIdleCallback();
      return;
    }
    if (instance != nullptr && instance != original) {
      state.freeInstance(instance);
    }
    if (state.registering || status == 0) {
      _release(state);
    } else {
      state.deregistering = false;
      _deregister(state);
    }
  }

  static void _release(_Registration state) {
    if (_registrations.remove(state.request.address) == null) return;
    if (identical(_active, state)) _active = null;
    state.freeInstance(state.request.ref.instance);
    calloc.free(state.request);
    calloc.free(state.cancelPointer);
    state.done.complete();
    _closeIdleCallback();
  }

  static void _freeInstance(Pointer<Void> instance) {
    try {
      _lib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('DnsServiceFreeInstance')(instance);
    } catch (e, st) {
      quietFailure('windows_mdns:148', e, st);
    }
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
  final Pointer<_ServiceCancel> cancelPointer;
  final int Function(Pointer<_RegisterRequest>) deregister;
  final void Function(Pointer<_ServiceCancel>) cancelRegistration;
  final void Function(Pointer<Void>) freeInstance;
  final done = Completer<void>();
  bool registering = true;
  bool stopping = false;
  bool deregistering = false;
  int deregisterAttempts = 0;
  _Registration(
    this.request,
    this.cancelPointer,
    this.deregister,
    this.cancelRegistration,
    this.freeInstance,
  );
}

final class _ServiceCancel extends Struct {
  external Pointer<Void> reserved;
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
