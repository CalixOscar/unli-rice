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
1. Install and launch **Unli Rice.app**.
2. **Home Screen:** Verify the initial guide notes ("Welcome to Unli Rice" and "How tags and the janitor work").
3. **Profile Builder:** Click **Build Profile** on Home (or go to **Setup → Who You Are & Profiles**). Select **Load Template… → Studio Standard** and complete the setup. Notice how profile notes (`Profile: identity`, `Profile: voice`, etc.) are created in the **Notes** tab.
4. **House Rules:** Navigate to **Setup → House Rules**. Select a preset (e.g., *Standard Memory*) and click **Save**.
5. **Notes & Search:** Go to **Notes** tab. Create a new note manually by clicking **+ New Note**. Enter a title and content, then search for it using the search bar.
6. **Brain Map:** Click **Brain Map** in the sidebar to view the visual graph linking notes and context profiles.
7. **Mirror Export:** Go to **Setup → Mirror Export** and click **Export Now**. Click **Open in Finder** to inspect the generated plain markdown mirror export folder.
8. **Trust Center:** Turn on **Advanced Mode** in settings to view **Trust Center**, confirming local vault integrity and connection diagnostics.

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
