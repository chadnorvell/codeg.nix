{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.codeg;

  mkDirenvAdapter =
    {
      adapterName,
      agentCommand,
      agentPathVariable,
    }:
    pkgs.writeShellApplication {
      name = adapterName;
      text = ''
        adapter_name=${lib.escapeShellArg adapterName}
        agent_command=${lib.escapeShellArg agentCommand}
        agent_path_variable=${lib.escapeShellArg agentPathVariable}
        envrc_dir="$(pwd -P)"

        while [[ ! -f "$envrc_dir/.envrc" ]]; do
          if [[ "$envrc_dir" == "/" ]]; then
            envrc_dir=""
            break
          fi

          envrc_dir="''${envrc_dir%/*}"
          [[ -n "$envrc_dir" ]] || envrc_dir="/"
        done

        if [[ -n "$envrc_dir" ]]; then
          if direnv_exports="$(
            cd "$envrc_dir"
            ${lib.getExe pkgs.direnv} export bash
          )"; then
            eval "$direnv_exports"
          else
            printf 'codeg-server: warning: direnv could not load %s; launching %s with the inherited user environment\n' \
              "$envrc_dir/.envrc" "$adapter_name" >&2
          fi
        fi

        if agent_path="$(type -P "$agent_command")"; then
          export "$agent_path_variable=$agent_path"
        fi

        wrapper_path="$(${lib.getExe' pkgs.coreutils "readlink"} -f "$0")"
        real_adapter=""
        while IFS= read -r candidate; do
          [[ -n "$candidate" ]] || continue
          candidate_path="$(${lib.getExe' pkgs.coreutils "readlink"} -f "$candidate")"

          if [[ "$candidate_path" != "$wrapper_path" ]]; then
            real_adapter="$candidate"
            break
          fi
        done < <(type -a -p "$adapter_name")

        if [[ -n "$real_adapter" ]]; then
          exec "$real_adapter" "$@"
        fi

        printf 'codeg-server: error: no real %s executable was found on PATH after the wrapper\n' \
          "$adapter_name" >&2
        exit 127
      '';
    };

  adapterConfigs = [
    {
      adapterName = "claude-agent-acp";
      agentCommand = "claude";
      agentPathVariable = "CLAUDE_CODE_EXECUTABLE";
    }
    {
      adapterName = "codex-acp";
      agentCommand = "codex";
      agentPathVariable = "CODEX_PATH";
    }
  ]
  ++
    lib.optionals
      (cfg.pi-acp.enable || builtins.any (p: (p.pname or p.name or "") == "pi-acp") cfg.adapterPackages)
      [
        {
          adapterName = "pi-acp";
          agentCommand = "pi";
          agentPathVariable = "PI_ACP_PI_COMMAND";
        }
      ];

  direnvAdapters = pkgs.symlinkJoin {
    name = "codeg-direnv-adapters";
    paths = map mkDirenvAdapter adapterConfigs;
  };

  realAdapters = pkgs.symlinkJoin {
    name = "codeg-acp-adapters";
    paths = cfg.adapterPackages ++ lib.optional cfg.pi-acp.enable cfg.pi-acp.package;
  };

  launcher = pkgs.writeShellScript "codeg-launcher" ''
    export PATH="${direnvAdapters}/bin:${realAdapters}/bin:''${PATH:-}"
    exec ${lib.getExe cfg.package}
  '';
in
{
  options.services.codeg = {
    enable = lib.mkEnableOption "the Codeg headless server";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "codeg.packages.\${system}.default";
      description = "The codeg-server package to run.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address codeg-server binds";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3080;
      description = "TCP port codeg-server listens on.";
    };

    adapterPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      defaultText = lib.literalExpression "[]";
      description = "The real ACP adapters Codeg resolves by name.";
    };

    pi-acp = {
      enable = lib.mkEnableOption "the pi-acp adapter for the Pi coding agent";

      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.pi-acp;
        defaultText = lib.literalExpression "codeg.packages.\${system}.pi-acp";
        description = "The pi-acp package to use.";
      };
    };

    dataDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "\${config.home.homeDirectory}/.local/share/codeg";
      description = "Overrides `CODEG_DATA_DIR`; null leaves Codeg's own default in place.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/codeg.env";
      description = ''
        Path to a systemd `EnvironmentFile` for secrets that must not reach the
        Nix store. Read at unit start, so it may live under /run/secrets.
      '';
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables for the codeg-server unit.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.codeg = {
      Unit.Description = "Codeg headless server";
      Install.WantedBy = [ "default.target" ];

      Service = {
        Type = "simple";
        ExecStart = "${launcher}";
        Environment = lib.mapAttrsToList (k: v: "${k}=${v}") (
          lib.filterAttrs (_: v: v != null) (
            {
              CODEG_HOST = cfg.host;
              CODEG_PORT = toString cfg.port;
              CODEG_MCP_BIN = "${cfg.package}/bin/codeg-mcp";
              CODEG_STATIC_DIR = "${cfg.package}/share/codeg/web";
              CODEG_DATA_DIR = cfg.dataDir;

              # Agents Codeg downloads itself ship their own OpenSSL, built to
              # look for /etc/ssl/cert.pem and the hashed /etc/ssl/certs/*.0
              # symlinks that NixOS does not create. Without this they cannot
              # complete a TLS handshake with their own backend; Antigravity
              # surfaces that as an empty turn with a local 502.
              SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            }
            // cfg.extraEnvironment
          )
        );
        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
        WorkingDirectory = config.home.homeDirectory;
        Restart = "on-failure";
        RestartSec = "30s";
        UMask = "0077";

        # Codeg supervises every agent subprocess it spawns, so the 1024 soft
        # default is easy to exhaust once several sessions are live.
        LimitNOFILE = 65536;
      };
    };
  };
}
