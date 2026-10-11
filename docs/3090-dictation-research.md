# Dictation on Reno's RTX 3090

Research date: 2026-10-10. Tracking: R3V-11. This is a source-based evaluation and integration proposal; no VM was accessed, no model was downloaded, and no inference benchmark was run.

## Recommendation

**Yes: a 24 GB RTX 3090 is a credible host for a private dictation service.** Start with an always-loaded model in a Linux VM and send completed recordings from R3VIB3 over a private authenticated endpoint. GPU availability inside that VM still needs verification. A bigger GPU or newer model alone does not establish better recognition of Reno's voice.

For primarily English, push-to-talk dictation, my first trial would be **Parakeet Unified English 0.6B**, with **Canary-Qwen 2.5B** as the accuracy challenger and the existing local Whisper setup as the control. Parakeet Unified is a newer English option than the frequently recommended Parakeet TDT v2/v3: NVIDIA's April 2026 release supports offline and streaming inference, punctuation, and capitalization. Its own matched evaluation reports 5.91% offline WER versus 6.04% for TDT v2. This is a reason to include it, not proof of a noticeable personal improvement. [Parakeet Unified model card](https://huggingface.co/nvidia/parakeet-unified-en-0.6b)

If English is not the only language, put **Qwen3-ASR 1.7B** into that initial trial. It covers 30 languages plus 22 Chinese dialects, under Apache 2.0. If technical names are the main problem, also prioritize it because its actual inference API accepts context text. Test a small vocabulary prompt against an empty prompt; do not assume biasing always helps. [Qwen model card](https://huggingface.co/Qwen/Qwen3-ASR-1.7B), [Qwen inference source](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/qwen3_asr.py)

If live words while speaking become a requirement, separately evaluate **Nemotron Speech Streaming English 0.6B**. It is explicitly cache-aware streaming, reusing encoder state instead of repeatedly processing old audio. R3VIB3 currently processes a completed file, so this would require a larger capture/UI change. [Nemotron English model card](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b)

## Candidates and tradeoffs

“Fits” below means a plausible single-model, short-utterance deployment at small batch size, not a measured peak or a promise of arbitrary concurrency.

| Candidate | Relevant strengths and limitations | 24 GB assessment / license |
| --- | --- | --- |
| **Parakeet Unified English 0.6B** | Preferred English first trial; offline plus buffered streaming. Native punctuation/capitalization. Advertised 160 ms minimum is audio context latency, not Mac-to-paste time. Streaming recomputes left context. | Strong fit candidate; NVIDIA Open Model License. [Source](https://huggingface.co/nvidia/parakeet-unified-en-0.6b) |
| **Parakeet TDT 0.6B v3** | Good speed-oriented multilingual baseline: 25 European languages, punctuation/capitalization and timestamps, 16 kHz mono input. Remains useful when those languages or the simpler established TDT path matter. | Strong fit candidate; CC BY 4.0. [Source](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) |
| **Canary-Qwen 2.5B** | English accuracy challenger with punctuation/capitalization. Card reports 5.63% mean WER on its Open ASR evaluation. Training audio was at most 40 seconds; longer input may degrade, so long dictation needs tested segmentation. Number/date formatting may still need inverse text normalization. | Plausible fit for short clips; use NeMo's SALM implementation. CC BY 4.0. [Source](https://huggingface.co/nvidia/canary-qwen-2.5b) |
| **Qwen3-ASR 1.7B** | Broad multilingual and accent coverage; context-enabled vocabulary experiment. Official Transformers and vLLM paths. Published benchmark claims are not a matched test against all rows here. | Plausible fit; the published repository has about 4.7 GB of weight files, which is **not** total runtime VRAM. Apache 2.0. [Model](https://huggingface.co/Qwen/Qwen3-ASR-1.7B), [files](https://huggingface.co/Qwen/Qwen3-ASR-1.7B/tree/main) |
| **Canary 1B v2** | 25 European languages, translation, punctuation/capitalization, timestamps. Useful multilingual alternative; translation is unnecessary for ordinary dictation. | Strong fit candidate; CC BY 4.0. [Source](https://huggingface.co/nvidia/canary-1b-v2) |
| **Whisper large-v3 / large-v3-turbo** | Essential familiar baseline. Turbo prunes decoder layers from 32 to 4, trading some accuracy for speed. Broad language coverage. Test large-v3 as well as turbo if accuracy is the objective. | OpenAI lists approximately 10 GB for large and 6 GB for turbo in its implementation. MIT. [Whisper repository](https://github.com/openai/whisper), [turbo card](https://huggingface.co/openai/whisper-large-v3-turbo) |
| **Nemotron English / Nemotron 3.5 ASR Streaming 0.6B** | English variant for English-only live capture. The June 2026 multilingual 3.5 model exposes 40 locales, but only 32 work out of the box; eight need adaptation. It supports punctuation and configurable 80–1120 ms audio chunks. NVIDIA still recommends its English variant for English-only use. | Strong fit candidates; English uses NVIDIA Open Model License, multilingual 3.5 uses OpenMDW-1.1. [English](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b), [3.5](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b) |
| **Voxtral Mini 4B Realtime 2602** | Native streaming alternative with 13 languages. Mistral recommends a 480 ms transcription delay. More model/runtime overhead than a 0.6B recognizer; reserve for a live-caption experiment. | vLLM's recipe specifies a GPU with at least 16 GB. Apache 2.0. [Model](https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602), [runtime recipe](https://recipes.vllm.ai/mistralai/Voxtral-Mini-4B-Realtime-2602) |

The model licenses above describe published checkpoints; serving software has its own licenses. Pin the tested checkpoint revision and runtime versions for repeatability.

## What the evidence does and does not establish

Parakeet v3 reports 6.34% mean English WER in its card; Canary-Qwen reports 5.63%. These justify testing both approaches, but card scores can differ in preprocessing, revision, segmentation and inference setup. They do not establish a personal dictation ranking. NVIDIA's reported WER excludes punctuation/capitalization, which are directly relevant to paste-ready prose. [Parakeet v3 evaluation](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), [Canary-Qwen evaluation](https://huggingface.co/nvidia/canary-qwen-2.5b)

Do not translate server throughput into a per-utterance latency promise. For example, faster-whisper's official large-v2 benchmark reports 4,525 MB VRAM in FP16 and 6,090 MB at batch eight, but it used an RTX 3070 Ti and long-form audio. It supports feasibility, not a 3090 timing claim or large-v3 measurement. [faster-whisper benchmark](https://github.com/SYSTRAN/faster-whisper#benchmark)

A useful dictation result must get names such as “Reno,” “R3VIB3,” “Death Eater,” project names, URLs, amounts, and negations right. Recognition, punctuation, and formatting are separate qualities. My recommendation is to measure the raw recognizer first. Add explicit, optional formatting only if it reduces editing without changing meaning. A general LLM cleanup pass should not silently rewrite a user's dictated text.

## VM and GPU plan

Proposed first deployment: one Linux guest that actually owns the GPU, a CUDA-capable runtime, one model process kept warm, one request at a time, and a bounded queue. Whole-device GPU passthrough grants the guest direct device access; host/hypervisor, firmware/IOMMU and driver configuration remain unknown. NVIDIA's generic passthrough guide describes the mechanism but is **not** certification of this specific GeForce/host combination. [NVIDIA passthrough documentation](https://docs.nvidia.com/vgpu/19.0/grid-vgpu-user-guide/using-gpu-pass-through.html)

Before installation, inspect the actual hypervisor, guest OS, CPU/RAM allocation, driver and `nvidia-smi` inside the guest. Confirm the free GPU memory and CUDA device visibility there, then run one inference. Prefer a container inside the GPU-owning guest if isolation is useful. Do not assume one passed-through card is concurrently available to other independent VMs.

My capacity expectation is that the 0.6–2.5B shortlist should leave ample room for short clips on 24 GB, but activations, audio length, decoder caches, runtime reservations and other workloads can dominate weight size. Start without quantization and without loading every candidate simultaneously. Measure peak memory, then test two concurrent requests only if needed. Qwen's official examples expose batch-size and GPU-memory controls; use conservative settings rather than copying its large-batch examples. [Qwen runtime documentation](https://github.com/QwenLM/Qwen3-ASR)

Keep cold startup distinct from warm latency: the model service should load once. App-visible time includes file conversion, network upload, queueing, inference, response parsing and paste. Initial product target for testing: warm p95 below 1.5 seconds after releasing push-to-talk for 5–20 second utterances on the normal network. This is an acceptance target, not a measured estimate.

## R3VIB3 integration

The current code already has the right separation:

- [`TranscriptionEngine`](../LocalTranscribePaste/Transcription/TranscriptionEngine.swift) accepts an audio file and returns text asynchronously.
- [`TranscriptionManager`](../LocalTranscribePaste/Transcription/TranscriptionManager.swift) converts to 16 kHz mono PCM and retains the temporary WAV until the engine callback completes.
- [`WhisperCLITranscriber`](../LocalTranscribePaste/Transcription/WhisperCLITranscriber.swift) invokes the bundled CLI with a local model path. Its present invocation supplies no vocabulary or language prompt.

Proposed implementation: a `RemoteTranscriber` using `URLSession` and an explicit provider configuration, with endpoint, remote model ID, language and optional vocabulary separate from the local model path. Keep local Whisper selectable. Show network errors and provide an explicit retry/provider choice; do not silently upload elsewhere or switch models. Capture, hotkeys and paste can remain the same for completed-clip transcription.

For a small private service, define a stable multipart `POST /v1/audio/transcriptions` contract returning `{"text":"..."}` and optional model/timing metadata. This is a **proposed adapter contract**, not a claim that every candidate exposes that endpoint. Wrap NeMo or faster-whisper behind it. Authenticate access and bind it to the intended private network; keep credentials in Keychain, delete server temporary audio, and omit raw audio/text from routine logs.

Qwen's documented `qwen-asr-serve` example uses `/v1/chat/completions` with audio content and an ASR-output parser, so it needs an adapter or a dedicated client. Its current streaming implementation re-feeds accumulated audio, supports one stream per state and rolls back recent tokens; it is not equivalent to Nemotron's cache-aware encoder. [Qwen server documentation](https://github.com/QwenLM/Qwen3-ASR), [streaming implementation](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/qwen3_asr.py)

Voxtral's documented live interface is WebSocket `/v1/realtime`. Adopting it means adding incremental microphone buffers, a session lifecycle and partial/final text handling. That is a later feature, not a drop-in replacement for the completed-file engine. [vLLM Voxtral recipe](https://recipes.vllm.ai/mistralai/Voxtral-Mini-4B-Realtime-2602)

## Small practical evaluation

1. Record 30 natural clips using Reno's normal microphone: ten everyday messages, ten technical/project sentences, five numbers/URLs/email addresses, and five noisy/hesitant examples. Include 2–5 second fragments and 30–60 second passages. Add five silence/keyboard/no-speech clips. Manually establish reference text before reviewing model outputs.
2. Run the same audio through current local Whisper, Parakeet Unified English, and Canary-Qwen. Add Qwen if vocabulary or multilingual coverage matters; add Whisper large-v3 if the existing local model is smaller. Keep input audio and language settings comparable, and record model/runtime revisions.
3. Measure normalized WER **and** raw punctuation/capitalization errors, exact named-entity/number accuracy, omitted/inserted meaning, hallucinations on silence, and time spent correcting each transcript. Preserve the exact spelling of “R3VIB3” in the entity metric even if word normalization removes it.
4. Measure warm stop-to-paste p50/p95, cold readiness, peak VRAM and failure rate. Record network conditions. For streaming candidates separately measure first stable text and finalization delay; do not compare their first partial token to a completed transcript.
5. Choose the model that saves editing time without unacceptable latency or semantic mistakes. Trial vocabulary context on a held-out half of the clips. Use a further 20 everyday recordings to check that the winner still wins outside the initial examples.

Remaining facts needed for implementation: VM host/hypervisor, guest OS and access, whether the 3090 can be reserved for this guest, usual languages, exact current Whisper model, microphone, and whether the desired interaction is push-to-talk or live text. These do not prevent the research recommendation; they determine deployment and the final model choice.
