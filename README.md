# Codeg for Nix

See the Codeg [repository](https://github.com/xintaofei/codeg) or [website](https://docs.codeg.app/)
for non-Nix information.

## Usage

Add this repo to your inputs, then do something like:

```nix
imports = [ inputs.codeg.homeManagerModules.default ];
services.codeg.enable = true;
```

The Codeg server runs as a user systemd service and the web UI is served at the default port.
Note that this flake doesn't currently provide the desktop (Tauri) app.

## Dealing with Codeg-provided agent binaries

Part of Codeg's value proposition is that you don't need to set up all of the ACP tools it needs,
because Codeg will download them for you. That's neat, but doesn't work well on NixOS, where generic
Linux binaries may not run out-of-the-box.

So you can get proper builds from a source like
[numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix) and shim those into Codeg like
this:

```nix
services.codeg.adapterPackages = with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
  claude-agent-acp
  codex-acp
];
```

For the Pi coding agent, Codeg attempts to install `pi-acp` via a global npm install, which fails
on NixOS. This flake provides a packaged `pi-acp` and a dedicated option:

```nix
services.codeg.pi-acp.enable = true;
```

The one tested exception to this is Antigravity CLI. Google doesn't provide a standalone ACP
adapter, so using the one provided by Codeg is the easiest option. Fortunately, it does work on
NixOS.

## Dealing with Nix shell/develop and direnv

If you're here, you're probably a heavy user of Nix shells/flakes for your projects. They work fine
with agent CLIs because you launch the CLI from within the shell. But Codeg doesn't, which is not
fine.

The Codeg service this flake provides shims in agent runtime adapters that recognize a direnv file
in the project directory and execute the agent runtime within the environment that direnv sets up.
So if your project has a `.envrc` that says `use flake`, the whole `nix develop` shell will be set
up first, then the agent runtime will be executed from within that environment, exactly as you would
want.

You don't need to do anything to take advantage of this, because it's built in for Claude Code,
Codex, and Pi (when `pi-acp` is enabled).
