import Flutter
import UIKit
import os
import Vision
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var storageChannel: FlutterMethodChannel?
  private var deviceChannel: FlutterMethodChannel?
  private var ocrChannel: FlutterMethodChannel?
  private var hostDiscovery: BonjourDiscovery?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let discoveryRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "OnDeviceDiscovery") {
      hostDiscovery = BonjourDiscovery(messenger: discoveryRegistrar.messenger())
    }
    if let ocrRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "OnDeviceOcr") {
      ocrChannel = FlutterMethodChannel(name: "ondevice_llm/ocr", binaryMessenger: ocrRegistrar.messenger())
      ocrChannel?.setMethodCallHandler { call, result in
        guard call.method == "recognize", let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else { result(FlutterMethodNotImplemented); return }
        let language = args["language"] as? String ?? "auto"
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if #available(iOS 16.0, *) { request.automaticallyDetectsLanguage = language == "auto" }
            if language != "auto" {
              let languages = ["en": "en-US", "fr": "fr-FR", "es": "es-ES"]
              if let hint = languages[language] { request.recognitionLanguages = [hint] }
            }
            let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path), options: [:])
            try handler.perform([request])
            let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first }
            let weight = recognized.reduce(0) { $0 + $1.string.count }
            let confidence: Double? = weight > 0 ? recognized.reduce(0.0) { $0 + Double($1.confidence) * Double($1.string.count) } / Double(weight) : nil
            let response: [String: Any] = ["text": recognized.map { $0.string }.joined(separator: "\n"), "confidence": confidence.map { $0 as Any } ?? NSNull()]
            DispatchQueue.main.async { result(response) }
          } catch { DispatchQueue.main.async { result(FlutterError(code: "ocr", message: error.localizedDescription, details: nil)) } }
        }
      }
    }
    if let deviceRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "OnDeviceDevice") {
      // Read-only device facts used to size models and defaults. Nothing leaves the device.
      deviceChannel = FlutterMethodChannel(name: "ondevice_llm/device", binaryMessenger: deviceRegistrar.messenger())
      deviceChannel?.setMethodCallHandler { call, result in
        switch call.method {
        case "memoryInfo":
          let total = ProcessInfo.processInfo.physicalMemory
          result(["totalBytes": Int64(total), "availableBytes": Int64(os_proc_available_memory()), "lowMemory": false])
        case "storageInfo":
          do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            result([
              "totalBytes": (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0,
              "availableBytes": (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            ])
          } catch {
            result(FlutterError(code: "STORAGE_INFO", message: error.localizedDescription, details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OnDeviceStorage") else { return }
    storageChannel = FlutterMethodChannel(name: "ondevice_llm/storage", binaryMessenger: registrar.messenger())
    storageChannel?.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "BACKUP_EXCLUSION", message: error.localizedDescription, details: nil))
      }
    }
  }
}

private class BonjourDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
  private let channel: FlutterMethodChannel
  private var published: NetService?
  private var browser: NetServiceBrowser?
  private var services: [NetService] = []
  private var found: [[String: Any]] = []
  private var reply: FlutterResult?
  private var revision = 0
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "ondevice_llm/discovery", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      switch call.method {
      case "advertise":
        guard let args = call.arguments as? [String: Any], let port = args["port"] as? Int, (1...65535).contains(port) else {
          result(FlutterError(code: "discovery", message: "Invalid port.", details: nil)); return
        }
        self.published?.stop()
        let service = NetService(domain: "local.", type: "_odllm._tcp.", name: "OnDevice LLM", port: Int32(port))
        self.published = service
        service.publish()
        result(nil)
      case "stop": self.published?.stop(); self.published = nil; result(nil)
      case "browse":
        guard self.reply == nil else { result(FlutterError(code: "discovery", message: "Discovery is already running.", details: nil)); return }
        self.reply = result; self.found = []; self.services = []; self.revision += 1
        let revision = self.revision
        let browser = NetServiceBrowser(); self.browser = browser; browser.delegate = self
        browser.searchForServices(ofType: "_odllm._tcp.", inDomain: "local.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
          if self?.revision == revision { self?.finish() }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func finish() {
    browser?.stop(); browser = nil
    services.forEach { $0.stop() }; services = []
    let result = reply; reply = nil
    result?(found)
  }
  func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
    guard reply != nil && services.count < 16 else { return }
    services.append(service); service.delegate = self; service.resolve(withTimeout: 4)
  }
  func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) { finish() }
  func netServiceDidResolveAddress(_ sender: NetService) {
    guard reply != nil, services.contains(sender) else { return }
    let hosts = (sender.addresses ?? []).compactMap { data -> String? in
      return data.withUnsafeBytes { raw -> String? in
        guard raw.count >= MemoryLayout<sockaddr>.size, let base = raw.baseAddress else { return nil }
        let address = base.assumingMemoryBound(to: sockaddr.self)
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(address, socklen_t(raw.count), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        return status == 0 ? String(cString: host) : nil
      }
    }
    if let host = hosts.first(where: { !$0.contains(":") }) ?? hosts.first {
      found.append(["name": sender.name, "host": host, "port": sender.port])
    }
  }
  deinit { published?.stop(); browser?.stop(); services.forEach { $0.stop() } }
}
