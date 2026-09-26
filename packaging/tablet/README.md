# Jev on the Replicator tablet

This setup reuses the tablet infrastructure already proven by the Replicator
project: Termux, a Debian `proot-distro`, and OpenAI's Secure MCP Tunnel client.
It does **not** require an Android APK, a VPS, Replit, Cloudflare, or a public
listener.

Jev itself remains hosted by TypeSafe. The tablet runs only the lightweight MCP
adapter and the outbound tunnel client.

## Architecture

```text
ChatGPT
  |
  | Secure MCP Tunnel
  v
Android tablet
  |
  +-- Termux
       |
       +-- Debian proot
            |
            +-- tunnel-client (profile: jev-tablet)
            +-- Node 22
            +-- @jkudish/jev-mcp
                     |
                     v
              TypeSafe hosted Jev
```

The Jev tunnel is separate from the existing `replicator-tablet` tunnel. Both
can run at the same time.

## What the installer reuses

By default it expects the working Replicator tunnel client at:

```text
~/replicator-tunnel/tunnel-client
```

and the existing Debian distribution named:

```text
debian
```

These defaults can be overridden with `JEV_TUNNEL_DIR` and
`JEV_DEBIAN_NAME`.

## One-time setup

1. In OpenAI Platform tunnel settings, create a dedicated tunnel for Jev and
   copy its `tunnel_...` identifier. A separate Jev tunnel keeps Replicator
   independent.
2. Put `install-jev-tablet.sh` and `jev-start` in the same folder on the
   tablet.
3. In Termux:

   ```sh
   chmod +x install-jev-tablet.sh jev-start
   ./install-jev-tablet.sh tunnel_YOUR_ID
   ```

4. Enter the OpenAI tunnel control-plane API key when prompted. Input is hidden.
   The installer does not write the key to disk.
5. If `jev-start` is beside the installer, the installer copies it to
   `$HOME/.local/bin/jev-start` automatically.

6. Start Jev:

   ```sh
   "$HOME/.local/bin/jev-start"
   ```

7. Enter the OpenAI control-plane API key and TypeSafe API key when prompted.
   Both inputs are hidden and are passed to Debian through standard input rather
   than command arguments or files.

## Connect ChatGPT

With `jev-start` running:

1. Open ChatGPT Plugins and create a developer-mode connection.
2. Name it **Jev**.
3. Choose **Tunnel** for Connection.
4. Select the dedicated Jev tunnel (or enter its `tunnel_id`).
5. Use **None** for MCP authentication. The private connection is authenticated
   by the OpenAI tunnel; the TypeSafe credential stays only in the tablet
   process.
6. Review the discovered Jev tools.

The server should expose the Jev tool family including `jev_verify`,
`jev_screen`, `jev_noul`, `jev_find`, `jev_rerank`, `jev_classify`,
`jev_decide`, `jev_compare`, `jev_extract`, `jev_review`, and
`jev_gate`.

After the tunnel is proven, package the repository's existing
`skills/jev/SKILL.md` with the private ChatGPT plugin so the assistant also
gets the tool-selection conventions, not only the raw tool schemas.

## Normal use

Keep `jev-start` running in its own Termux session. Replicator may continue
running in its existing session/profile at the same time.

The launcher intentionally does not save either secret. If the Termux session
ends, enter the keys again on restart unless you later choose a separate secure
credential-storage method.

## Diagnostics

Check the installed runtime without starting the tunnel:

```sh
"$HOME/.local/bin/jev-start" --doctor
```

The one-time installer also runs:

```text
tunnel-client doctor --profile jev-tablet --explain
```

after profile creation.

If Android suspends the Termux process, use the same background/battery
allowances already required by the Replicator tablet host. This setup does not
alter Android battery policy automatically.
