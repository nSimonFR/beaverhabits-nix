# NixOS module for BeaverHabits — self-hosted habit tracker (daya0576/beaverhabits).
#
# Usage:
#   inputs.beaverhabits-nix.url = "github:nSimonFR/beaverhabits-nix";
#
#   imports = [ inputs.beaverhabits-nix.nixosModules.beaverhabits ];
#   services.beaverhabits = {
#     enable = true;
#     environmentFile = "/run/agenix/beaverhabits-env";  # session/JWT secrets
#     settings.APP_URL = "https://habits.example.ts.net";
#   };
#
# The environmentFile should export the three secrets BeaverHabits signs with
# (random values; changing them logs everyone out / invalidates reset tokens):
#   NICEGUI_STORAGE_SECRET=...
#   JWT_SECRET=...
#   RESET_PASSWORD_TOKEN_SECRET=...
#
# Storage is a single SQLite database (HABITS_STORAGE=DATABASE). No external DB.
# SQLAlchemy creates the schema on first start — there is no migration step.
{ self, uv2nix, pyproject-nix, pyproject-build-systems }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.beaverhabits;
  defaultPackage = pkgs.callPackage (self + "/package.nix") {
    inherit uv2nix pyproject-nix pyproject-build-systems;
  };

  appEnv = {
    ENV = "production";
    HOST = cfg.host;
    PORT = toString cfg.port;
    HABITS_STORAGE = "DATABASE";
    DATABASE_URL = "sqlite+aiosqlite:///${cfg.stateDir}/habits.db";
    NICEGUI_STORAGE_PATH = "${cfg.stateDir}/.nicegui";
  } // cfg.settings;
in
{
  options.services.beaverhabits = {
    enable = lib.mkEnableOption "BeaverHabits habit tracker";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "The BeaverHabits derivation to use.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address the gunicorn server binds to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 13342;
      description = "Port the gunicorn server listens on.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/beaverhabits";
      description = "Persistent state directory (holds habits.db and .nicegui/).";
    };

    user = lib.mkOption { type = lib.types.str; default = "beaverhabits"; };
    group = lib.mkOption { type = lib.types.str; default = "beaverhabits"; };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to a file exporting secrets as KEY=VALUE lines (NICEGUI_STORAGE_SECRET,
        JWT_SECRET, RESET_PASSWORD_TOKEN_SECRET). Keeps them out of the world-
        readable Nix store.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { APP_URL = "https://habits.example.ts.net"; MAX_USER_COUNT = "1"; };
      description = "Extra environment variables merged into the BeaverHabits service (see beaverhabits/configs.py).";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = lib.mkIf (cfg.user == "beaverhabits") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      createHome = false;
    };
    users.groups.${cfg.group} = lib.mkIf (cfg.group == "beaverhabits") { };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir}          0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/.nicegui 0750 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.beaverhabits = {
      description = "BeaverHabits — habit tracker web server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = appEnv;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/beaverhabits";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = baseNameOf cfg.stateDir;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "10s";
        # Hardening — no DynamicUser so the nightly SQLite backup can read the DB
        # as a stable uid regardless of whether the server is awake (idle-sleep).
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ cfg.stateDir ];
      } // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
    };
  };
}
