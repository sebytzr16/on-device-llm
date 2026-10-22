# Model settings contract

Generated from `SettingSpec.all` by `dart run tool/generate_model_settings_reference.dart`.

The global inference editor, model/preset/chat editors, override validation and this reference use the same registry. Privacy, appearance, voice and remote credentials have separate global controls and cannot be changed by a model/preset/chat override.

Cascade: app defaults → phone defaults → the model’s recommended sampling (its model card, Hugging Face `generation_config.json`, the GGUF’s `general.sampling.*` keys) → user → model → preset → project → chat → turn. Project instructions join the system prompt; project knowledge defaults can be overridden by the chat.

| Key | Label | Type | Default | Bounds/choices | Reload |
| --- | --- | --- | --- | --- | --- |
| `batchSize` | Batch size | integer | 0 | 0 … 4096 | yes |
| `microBatchSize` | Micro batch size | integer | 0 | 0 … 4096 | yes |
| `maxSearchResults` | Search results | integer | 5 | 1 … 10 | no |
| `searchQueryPlanning` | Plan search queries | boolean | true |  | no |
| `searchAgain` | Search again when pages fall short | boolean | true |  | no |
| `wikipediaLookup` | Add the Wikipedia article | boolean | true |  | no |
| `thinkOnSearch` | Think before answering from sources | boolean | true |  | no |
| `researchTimeBudgetSeconds` | Research time (seconds) | integer | 25 | 10 … 180 | no |
| `xtcProbability` | XTC probability | number | 0.0 | 0 … 1 | no |
| `xtcThreshold` | XTC threshold | number | 0.1 | 0 … 0.5 | no |
| `topNSigma` | Top-n sigma (-1 = off) | number | -1.0 | -1 … 10 | no |
| `dryMultiplier` | DRY multiplier | number | 0.0 | 0 … 5 | no |
| `dryBase` | DRY base | number | 1.75 | 1 … 4 | no |
| `dryAllowedLength` | DRY allowed length | integer | 2 | 1 … 32 | no |
| `dryPenaltyLastN` | DRY penalty window (-1 = context) | integer | -1 | -1 … 8192 | no |
| `samplerOrder` | Sampler order | stringList | [penalties, dry, top_n_sigma, top_k, typ_p, top_p, min_p, xtc, temperature] |  | no |
| `ropeFreqBase` | RoPE frequency base | number | 0.0 | 0 … 1000000000 | yes |
| `ropeFreqScale` | RoPE frequency scale | number | 0.0 | 0 … 1 | yes |
| `yarnExtFactor` | YaRN extension factor | number | -1.0 | -1 … 1 | yes |
| `yarnAttnFactor` | YaRN attention factor | number | 1.0 | 0 … 8 | yes |
| `yarnBetaFast` | YaRN beta fast | number | 32.0 | 0 … 128 | yes |
| `yarnBetaSlow` | YaRN beta slow | number | 1.0 | 0 … 128 | yes |
| `yarnOrigCtx` | YaRN original context | integer | 0 | 0 … 1048576 | yes |
| `draftMaxTokens` | Draft tokens | integer | 6 | 1 … 16 | yes |
| `imageMaxTokens` | Photo token budget | integer | 1024 | 64 … 16384 | yes |
| `systemPrompt` | Custom instructions | text |  |  | no |
| `temperature` | Temperature | number | 0.7 | 0 … 2 | no |
| `topP` | Top-P | number | 0.95 | 0 … 1 | no |
| `minP` | Min-P | number | 0.05 | 0 … 1 | no |
| `topK` | Top-K | integer | 40 | 0 … 200 | no |
| `typicalP` | Typical-P | number | 1.0 | 0 … 1 | no |
| `repetitionPenalty` | Repetition penalty | number | 1.0 | 1 … 2 | no |
| `presencePenalty` | Presence penalty | number | 0.0 | -2 … 2 | no |
| `frequencyPenalty` | Frequency penalty | number | 0.0 | -2 … 2 | no |
| `repeatLastN` | Penalty window (tokens) | integer | 64 | 0 … 4096 | no |
| `maxTokens` | Max tokens | integer | 1024 | 64 … 65536 | no |
| `seed` | Seed (0 = random) | integer | 0 | 0 … 2147483647 | no |
| `stopSequences` | Stop sequences | stringList | [] |  | no |
| `thinkingModeEnabled` | Thinking mode | boolean | false |  | no |
| `thinkingBudgetTokens` | Thinking budget (0 = unlimited) | integer | 0 | 0 … 65536 | no |
| `webMode` | Web research | choice | off | off, auto, always | no |
| `researchLoop` | Model-driven research | boolean | false |  | no |
| `maxPagesRead` | Pages to read | integer | 3 | 1 … 8 | no |
| `evidencePassages` | Passages given to the model | integer | 6 | 2 … 16 | no |
| `knowledgeCollection` | Knowledge collection | text |  |  | no |
| `toolsEnabled` | Tool calling | boolean | false |  | no |
| `toolChoice` | Tool use | choice | auto | auto, required | no |
| `toolCalculator` | Calculator | boolean | true |  | no |
| `toolWeb` | Web tools | boolean | true |  | no |
| `toolDocuments` | Document tools | boolean | true |  | no |
| `toolMaxRounds` | Tool rounds per answer | integer | 4 | 1 … 8 | no |
| `responseFormat` | Response format | choice | text | text, json, json_schema, gbnf | no |
| `jsonSchema` | JSON schema | text |  |  | no |
| `grammar` | GBNF grammar | text |  |  | no |
| `contextSize` | Context size | integer | 4096 | 512 … 1048576 | yes |
| `promptCache` | Keep conversation in context | boolean | true |  | no |
| `backend` | Backend | choice | auto | auto, cpu, opencl, vulkan, metal | yes |
| `nGpuLayers` | GPU layers | integer | 999 | 0 … 999 | yes |
| `cpuThreads` | CPU threads (decode, 0 = auto) | integer | 0 | 0 … 16 | yes |
| `batchThreads` | CPU threads (prefill, 0 = auto) | integer | 0 | 0 … 16 | yes |
| `flashAttention` | Flash attention | boolean | true |  | yes |
| `kvCacheType` | K cache type | choice | fp16 | fp16, q8_0, q4_0 | yes |
| `vCacheType` | V cache type (empty = same as K) | choice |  | , fp16, q8_0, q4_0 | yes |
| `ropeScaling` | RoPE scaling | choice | model | model, none, linear, yarn | yes |
| `draftModelId` | Draft model (speculative decoding) | text |  |  | yes |
