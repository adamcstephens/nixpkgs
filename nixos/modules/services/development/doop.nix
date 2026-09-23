{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.doop;
in
{
  options.services.doop = {
    enable = lib.mkEnableOption "doop server";

    package = lib.mkPackageOption pkgs "doop" { };

    address = lib.mkOption {
      type = lib.types.str;
      description = "ip address to listen on";
      default = "127.0.0.1";
    };

    port = lib.mkOption {
      type = lib.types.int;
      description = "port to listen on";
      default = 4400;
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      description = "Environment files";
      default = [ ];
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = ''
        Service environnment.

        https://github.com/kgoedecke/doop/blob/main/.env.example
      '';
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    services.doop.settings = {
      HOST = cfg.address;
      PORT = toString cfg.port;
    };

    systemd.services.doop = {
      enable = true;
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];

      environment = {
        HOME = "%S/doop";
        PUPPETEER_SKIP_DOWNLOAD = "true";
        PUPPETEER_CACHE_DIR = "%S/doop/.cache/puppeteer";
      }
      // cfg.settings;

      confinement = {
        enable = true;
        mode = "full-apivfs";
        binSh = null;
        packages = lib.optionals config.fonts.fontconfig.enable [ config.environment.etc.fonts.source ];
      };

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        EnvironmentFile = cfg.environmentFiles;
        WorkingDirectory = "%S/doop";

        DynamicUser = true;
        StateDirectory = "doop";
        StateDirectoryMode = "0700";
        RuntimeDirectory = [ "doop" ];
        RuntimeDirectoryMode = "0700";

        BindReadOnlyPaths = [
          "/etc/ssl/certs"
          "/etc/static/ssl/certs"
          config.environment.etc."ssl/certs/ca-certificates.crt".source

          "/etc/hosts"
          "/etc/static/hosts"

          "/etc/nsswitch.conf"
          "/etc/static/nsswitch.conf"

          "/etc/resolv.conf"
        ]
        ++ lib.optionals config.fonts.fontconfig.enable [ "/etc/fonts" ];

        AmbientCapabilities = "";
        CapabilityBoundingSet = [ "" ] ++ lib.optionals (cfg.port < 1024) [ "CAP_NET_BIND_SERVICE" ];
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = "strict";
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        # Chromium creates these namespaces for its own sandbox.
        RestrictNamespaces = [
          "user"
          "pid"
          "net"
        ];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "@pkey"
          "~@privileged @resources"
          # Optional scheduling requests must fail without killing Chromium.
          "~setpriority:EPERM"
          "~sched_setaffinity:EPERM"
          # Chromium drops capabilities and chroots inside its user namespace.
          "capset"
          "chroot"
        ];
        UMask = "0077";
      };
    };
  };
}
