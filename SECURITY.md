# Security

## Reporting a problem

Please report security problems privately. On GitHub, use **Security >
Report a vulnerability** on this repository. Do not open a public issue.
Include the app version (Settings > About), the phone model and the steps
that show the problem.

## What the app sends over the network

The app runs its models locally (on Android and Windows) and operates a local or LAN model server when hosting is enabled by the user. It connects only to:
- model and voice-pack downloads initiated by the user (Hugging Face and sherpa-onnx GitHub releases at pinned revisions);
- opt-in public web search (DuckDuckGo HTML/lite/news endpoints);
- opt-in Wikipedia language APIs and news RSS feeds;
- the manual update check, only when the user presses **Check for updates** in Settings > About: one request to the public GitHub Releases API for this repository, with a generic `OnDeviceLLM` User-Agent and no account, device or usage identifier;
- user-configured remote servers (OpenAI-compatible APIs or hosted endpoints);
- user-approved Model Context Protocol (MCP) executables that perform their own network calls;
- local peer discovery and TLS/HTTPS pairing requests over loopback or local Wi-Fi.

Remote API keys are kept in platform-backed secure storage (Android Keystore / Windows DPAPI via flutter_secure_storage) and are never written to chats, exports or logs. Arbitrary header, tool or stderr logs may contain debug content and should not be treated as strictly secret-free. Anything that opens a new kind of connection without user action should be reported.

## Serving and hosting (Android and Windows)

The app can host local models over HTTP/HTTPS on Android and Windows for paired client apps or remote integrations. Hosting binds to local network interfaces only when explicitly enabled. TLS connections require pairing certificates and typed/QR pairing codes. Legacy plaintext LAN HTTP is retained only for backwards compatibility and should be migrated to TLS. Tokens issued upon pairing grant access to hosting APIs and must be revoked or re-paired if a device is lost.

## Model and file integrity vs. authenticity

- **Downloads:** First-party model files, voice packs, and native assets downloaded by the app are verified against their pinned sizes and SHA-256 hashes before loading.
- **Imported files:** GGUF model files and documents imported by the user undergo structural checks (such as GGUF magic numbers and version parsing), but structural validity does not guarantee publisher authenticity or safety. Importing untrusted files is at the user's risk.

## Unsigned builds and release signatures

Production builds for Android and Windows require proper publisher signing. Unsigned or debug-signed builds lack cryptographic verification of publisher identity, and users or administrators must verify binaries and installer signatures before deployment.
