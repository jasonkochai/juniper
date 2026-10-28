# Connect more tools

Juniper is my example: Telegram, Apple Mail and Calendar, Brave search, Obsidian. OpenClaw connects to far more. This page lists what OpenClaw 2026.10.5 supports out of the box or as an official plugin (from its [features page](https://docs.openclaw.ai/concepts/features) and [plugin inventory](https://docs.openclaw.ai/plugins/plugin-inventory)), and how to add something to Juniper without opening it up.

## What you can plug in

**Chat channels.** Telegram, WebChat, A2A and Reef ship with OpenClaw. Official plugins add WhatsApp, Signal, Discord, Slack, iMessage, Matrix, Microsoft Teams, Google Chat, Mattermost, Nextcloud Talk, Synology Chat, LINE, IRC, Twitch, Nostr, SMS (Twilio), Voice Call and more. One gateway can serve several channels at once.

**Model providers.** Anthropic, OpenAI, Google, xAI, Mistral, DeepSeek, Groq, Cerebras, OpenRouter, Amazon Bedrock, Microsoft Foundry, Hugging Face, NVIDIA, Together and others. For local models: Ollama, LM Studio, llama.cpp, vLLM, SGLang, any OpenAI- or Anthropic-compatible endpoint, and Apple's on-device models ([local-llm.md](local-llm.md)).

**Web search.** Brave (Juniper's default), Tavily, Exa, Perplexity, Firecrawl, DuckDuckGo, Gemini, Grok, Kimi, MiniMax, Ollama Web Search and SearXNG. SearXNG is self-hosted, so it fits a fully private setup.

**Images, video and voice.** Image and video generation through Google, fal, Runway, Alibaba and ComfyUI (which can run locally). Speech in and out through ElevenLabs, Deepgram, Azure Speech, Microsoft and local TTS.

**Memory and knowledge.** Built-in memory, an Obsidian-friendly wiki memory (`memory-wiki`) and a LanceDB memory plugin.

**Your devices.** iOS and Android nodes (camera, location, voice), a macOS menu bar app, a Windows hub and a Linux node with desktop notifications.

**Meetings and work tools.** Plugins for Google Meet, Zoom and Teams meetings, GitHub link previews, a workboard, and team reports.

**Secrets.** 1Password and HashiCorp Vault as secret stores instead of a plain `.env`.

**Anything with an MCP server.** This is how Juniper connects Apple Mail and Calendar. Any MCP server works, local (`command` + `args`) or remote (`url`): Home Assistant, Notion, GitHub, Todoist, your own scripts. For hundreds of SaaS apps behind OAuth, an integration layer such as Composio exposes them as one MCP server.

**Skills.** ClawHub has community skills. Treat them like code from a stranger: read [the vetting list](security.md#skill-vetting-before-any-clawhub-install) first.

## Adding one to Juniper safely

Every new tool widens what an agent can do. The pattern Juniper uses for its own tools:

1. **One agent owns it.** Add the tool to that agent's `tools.allow` (or `alsoAllow` for the hub) in the phase config, nowhere else.
2. **Everyone else denies it.** For an MCP server named `home`, add `"home__*"` to the `deny` list of every other agent.
3. **Filter the tools.** Use `toolFilter.include` on MCP servers so only the tools you want exist. Leave out anything that sends, deletes, buys or posts unless that agent asks you first.
4. **Pin versions.** `package@1.2.3` for MCP servers, `--pin` for plugins.
5. **Keep exec and Code Mode off.** `tools.codeMode: false` stays, and no agent gets `exec`, `process` or the browser.
6. **Audit.** Run `host.sh check` and the tool check in that agent's topic.

Ask Claude Code to do it: "Add Home Assistant to Juniper for a new agent that can only read sensor states." It follows these rules from [CLAUDE.md](../CLAUDE.md).
