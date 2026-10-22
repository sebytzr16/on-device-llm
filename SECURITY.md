# Security

## Reporting a problem

Please report security problems privately. On GitHub, use **Security >
Report a vulnerability** on this repository. Do not open a public issue.
Include the app version (Settings > About), the phone model and the steps
that show the problem.

## What the app sends over the network

The app runs its models on the phone and has no server of its own. It
connects only to:

- the model and voice-pack downloads the user starts (Hugging Face and the
  sherpa-onnx GitHub releases, at pinned revisions);
- DuckDuckGo, when web search is on;
- Wikipedia and the news RSS feeds, when those lookups are on;
- the remote server the user configures (an OpenAI-compatible server such as
  LM Studio, or a hosted API), only while a remote connection is on.

Remote API keys are kept in the Android Keystore and are never written to
chats, exports or logs. Anything that opens a new kind of connection is a
security-relevant change and should be reported if it happens without the
user turning it on.

## Model files

Downloaded files are checked against their pinned size and hash before they
are loaded. A GGUF the user imports is not checked, and loading an untrusted
model file is at the user's own risk.
