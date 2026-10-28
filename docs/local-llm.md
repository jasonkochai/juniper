# Fully local with your own models

By default Juniper uses Claude Haiku and Gemini Flash-Lite in the cloud. You can swap them for a model running on your own hardware, so prompts, emails, calendar entries and notes never reach a model provider.

What stays outside your network even then:

- **Telegram** carries the chat itself (the bot polls Telegram's servers).
- **Events and News** still fetch event feeds and web pages, and News uses Brave Search. Leave them out if you want no outside requests at all.
- **iCloud Mail and Calendar** are still Apple's servers; the local model only reads what the connectors fetch.

## Pick a layout

| Layout | OpenClaw runs on | The model runs on | `baseUrl` |
| --- | --- | --- | --- |
| **One device** | your Mac or gaming PC (`HOST_TYPE=local`) | the same machine | `http://host.docker.internal:11434` |
| **Two devices** | a Raspberry Pi or home server, always on (`linux` or `ugos`) | an old gaming PC or a MacBook in your home network | `http://<that machine's LAN IP>:11434` |
| **Hybrid** | your home server | cloud models, optionally the local model for agents you pick | both, see "Mixing cloud and local" below |

Two devices is the sweet spot for a private setup: the small box stays on and keeps the schedule, the big machine only has to be awake when an agent thinks. Give the model machine a fixed LAN address in your router.

Everything below follows the OpenClaw 2026.10.5 docs: [Ollama provider](https://docs.openclaw.ai/providers/ollama), [local models](https://docs.openclaw.ai/gateway/local-models), [Docker networking](https://docs.openclaw.ai/install/docker/networking-and-storage), [audio](https://docs.openclaw.ai/nodes/audio).

## 1. Pick a model and a machine

- **Tool calling is required.** Every Juniper agent works through tools. OpenClaw's Ollama discovery only accepts models "with tool support and at least 16K of context".
- **Context:** plan for 32K tokens (`num_ctx` 32768). OpenClaw warns below 8K and refuses below 4K of free context.
- **Hardware:** a 7–14B model with tool support runs on a Mac with Apple Silicon or a PC with a recent GPU. A home server without a GPU (most of them, and a Raspberry Pi) is too slow; run the model on another machine in your home and point Juniper at it.
- **Photos:** to let the hub read images, use a vision model and set `"input": ["text", "image"]`.
- Local models are slower and less careful than Haiku, and "skip provider-side filters". Juniper's narrow tool lists matter even more here.

## 2. Run the model server

With [Ollama](https://ollama.com):

```sh
ollama pull <model>                       # a tool-capable model, e.g. one from the Qwen family
OLLAMA_HOST=0.0.0.0:11434 ollama serve    # listen where Docker can reach it
```

`0.0.0.0` also exposes Ollama to your LAN. Block port 11434 from other devices with your firewall, or bind to the Docker bridge address only.

Any server with an OpenAI-style `/v1/chat/completions` endpoint works too (LM Studio, llama.cpp, vLLM, MLX); see the variant in step 3.

## 3. Point Juniper at it

**How the container reaches the model server.** Inside the container `127.0.0.1` is the container itself. Use `host.docker.internal`:

- **Docker Desktop** (local installs) provides it already.
- **Linux** (`linux`, `ugos`) needs it added under `openclaw-gateway` in `host/docker-compose.yaml`:

  ```yaml
      extra_hosts:
        - "host.docker.internal:host-gateway"
  ```

- **Model on another machine:** use its LAN address instead, e.g. `http://192.168.1.20:11434`.

**Config changes.** Apply these to every phase config you use (`host/config/openclaw.phaseN.json`, strict JSON), with `<model>` being the Ollama model name without the `ollama/` prefix:

1. Add a top-level `models` block:

   ```json
   "models": {
     "mode": "merge",
     "providers": {
       "ollama": {
         "baseUrl": "http://host.docker.internal:11434",
         "apiKey": "ollama-local",
         "api": "ollama",
         "timeoutSeconds": 300,
         "models": [
           {
             "id": "<model>",
             "name": "<model>",
             "input": ["text"],
             "contextTokens": 32768,
             "params": { "num_ctx": 32768, "keep_alive": "15m" }
           }
         ]
       }
     }
   }
   ```

   Use Ollama's native API as shown. The docs warn: "Do not use the `/v1` OpenAI-compatible URL … It breaks tool calling." Keep `contextTokens` and `num_ctx` equal.

2. In `agents.defaults`:
   - `"model": { "primary": "ollama/<model>", "fallbacks": [] }`
   - `"models": { "ollama/<model>": { "alias": "local" } }`
   - `"modelPolicy": { "allow": ["ollama/*"] }`
   - delete `mediaModels` (image generation).
3. In every entry under `agents.entries` that has a `model`, set it to `{ "primary": "ollama/<model>", "fallbacks": [] }`.
4. Phase 4: remove `"image_generate"` from main's `alsoAllow` and add it to main's `deny`. Replace `tools.media` with `"media": { "audio": { "enabled": false } }`.
5. Leave `tools.codeMode: false` exactly as it is.

**OpenAI-compatible server instead of Ollama.** Replace the `ollama` provider with:

```json
"local": {
  "baseUrl": "http://host.docker.internal:8000/v1",
  "apiKey": "sk-local",
  "api": "openai-completions",
  "timeoutSeconds": 300,
  "models": [{ "id": "<model>", "name": "Local", "reasoning": false, "input": ["text"], "contextWindow": 32768, "maxTokens": 8192 }]
}
```

Model refs then are `local/<model>`, and `modelPolicy.allow` becomes `["local/*"]`. LM Studio listens on port 1234.

**Secrets.** Remove `ANTHROPIC_API_KEY` and `GEMINI_API_KEY` from `.env` (or leave them empty). Voice auto-detection checks configured provider keys first, so a leftover Gemini key would still send voice memos to Google.

## 4. Apply and check

```sh
python3 scripts/render.py                                   # and rsync on a server
host.sh compose                                             # picks up extra_hosts
sudo JUNIPER_AGENT_MODEL=ollama/<model> bash ~/juniper/host.sh agent calendar   # local: drop sudo, use build/host/host.sh
host.sh config 1                                            # or the phase you're on
openclaw infer model run --gateway --model ollama/<model> --prompt "Reply with exactly: pong" --json
openclaw models list --agent main --provider ollama
```

`JUNIPER_AGENT_MODEL` makes `host.sh agent` register the local model instead of the cloud default; `config N` sets the full model block afterwards either way.

Then run the usual tool check in each topic (setup.md, Phase 2). Local models use OpenClaw's structured Tool Search, so `tool_search`, `tool_describe` and `tool_call` appear, as in the cloud setup.

## Mixing cloud and local (hybrid)

Models are set per agent, so you can keep the sensitive agents local and let the rest use the cloud:

- Keep the cloud defaults, add the `models` block from step 3, and add `"ollama/*"` to `agents.defaults.modelPolicy.allow` next to the cloud models.
- Set only the agents you choose to `{ "primary": "ollama/<model>", "fallbacks": [] }`. Email is the obvious one: your inbox never reaches a model provider.
- Keep voice and image generation on the cloud, or turn them off as below.

A cloud model in an agent's `fallbacks` keeps it working when the model machine is off, but that run then goes to the cloud. Leave `fallbacks` empty for agents that must stay local.

## Voice and images

- **Voice memos:** off. Local transcription needs a CLI such as `whisper-cli` inside the container, which means building your own image; Juniper sticks to the pinned official one.
- **Image generation:** off. The local routes (ComfyUI through an extra plugin, or LocalAI with a weakened network policy) aren't worth the extra surface for a showcase.

## Things to know

- If the model server is down, scheduled jobs are marked `skipped` instead of falling back to a cloud model.
- Smaller models follow the instruction files less reliably. Test the confirmations ("Create this event? yes/no") before you rely on them.
- The cost table drops to $0 in API fees; you pay in electricity and speed.
