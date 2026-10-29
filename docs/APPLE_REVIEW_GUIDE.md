# App Store Reviewer Guide & Sample MCP Client Configurations

This document provides sample configuration files and verification steps for Apple App Review.

---

## 1. Permanent Hosted Sample Configurations

For review verification, sample configuration files for standard Model Context Protocol (MCP) clients are hosted permanently at:

- **JSON Configuration (Claude Desktop / Cursor / VS Code / MCP Clients):**  
  `https://raw.githubusercontent.com/CalixOscar/unli-rice/main/docs/sample_configs/claude_desktop_config.json`

- **Generic MCP JSON Configuration (`.mcp.json`):**  
  `https://raw.githubusercontent.com/CalixOscar/unli-rice/main/docs/sample_configs/mcp_config.json`

- **TOML Configuration (Codex / TOML-based clients):**  
  `https://raw.githubusercontent.com/CalixOscar/unli-rice/main/docs/sample_configs/config.toml`

### Sample Configuration Content (`mcpServers` JSON format):

```json
{
  "mcpServers": {
    "unlirice": {
      "command": "/Applications/Unli Rice.app/Contents/MacOS/unlirice-mcp",
      "args": []
    }
  }
}
```

### Sample Configuration Content (TOML format):

```toml
[mcp_servers.unlirice]
command = "/Applications/Unli Rice.app/Contents/MacOS/unlirice-mcp"
args = []
```

---

## 2. Architecture & Overview

Unli Rice is a standalone native macOS productivity application that manages a persistent, append-only note vault on your Mac.

- **Standalone App:** The app functions 100% locally without requiring any external cloud subscription, API key, account, or internet connection.
- **Embedded MCP Helper:** The app bundle contains an independently sandboxed binary helper executable at `/Applications/Unli Rice.app/Contents/MacOS/unlirice-mcp`.
- **Interoperability:** When an external MCP client (such as Claude Desktop, Cursor, Goose, or Windsurf) is installed, it launches the embedded `unlirice-mcp` binary via standard input/output (stdio) to create and query notes in the app's local memory store.

---

## 3. Review Verification Steps

### Option A: Standalone Verification (No External Client Required)
Names below are the buttons in Unli Rice 1.4. The sidebar has two sections, Grounding and Guardrails, with Setup at the bottom.
1. Install and launch **Unli Rice.app**. Home opens.
2. **Notes:** Click **Notes** in the sidebar. A new vault starts with two guide notes, "Welcome to Unli Rice" and "How tags and the janitor work". Click **New Note**, enter a title and content, save it, then find it with the search field.
3. **House Rules:** Click **What your AI should always do**. Select a template (for example *Engineering Guardrails*) and click **Use as Draft**. Then open **Setup → AI Tools**, scroll to **House Rules** and click **Save to notes**. The rules appear as a note in **Notes**.
4. **Mirror export:** Click **The folder your AI can read**, then **Export Now** and **Open in Finder** to inspect the plain-Markdown copy.
5. **Trust Center:** Click **Trust Center**, then **Run checks**, to see vault integrity and connection diagnostics.
6. **Optional features:** Open **Setup → Extras**. Projects, To do, Map, Your year so far, Separate memories (with the Profile Builder), PDF and ZIP export and the iPhone Capture card are off by default for a new install. Turning one on adds it to the sidebar (or the File menu); turning it off only hides it. For example, turn on **Map** and click **Map** in the sidebar to see the note graph.

### Option B: Verification with an MCP Client (e.g., Claude Desktop or MCP Inspector)
1. Install **Unli Rice.app** into `/Applications`.
2. Open your MCP client's configuration file (e.g., `~/Library/Application Support/Claude/claude_desktop_config.json`).
3. Add the `unlirice` server entry from the sample configuration above.
4. Launch/restart the MCP client.
5. Ask the AI assistant to read or write a note (e.g., *"Save a note in Unli Rice titled Test Note"*).
6. Switch back to **Unli Rice.app** and open the **Notes** tab to verify that the note was created and attributed to the connected client.
7. Alternatively, test the binary using the open-source MCP inspector tool:
   ```bash
   npx @modelcontextprotocol/inspector /Applications/Unli\ Rice.app/Contents/MacOS/unlirice-mcp
   ```

---

## 4. Availability & Regional Compliance Note

- This app does not host, bundle, or distribute any AI models or generative deep synthesis services.
- In accordance with local regulations, the **China mainland** storefront availability has been deselected in App Store Connect for this submission.
