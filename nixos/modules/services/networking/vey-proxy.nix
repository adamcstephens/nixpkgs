{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.vey-proxy;
  format = pkgs.formats.yaml { };
  configFile = format.generate "vey-proxy.yaml" cfg.settings;
in
{
  options.services.vey-proxy = {
    enable = lib.mkEnableOption "VEY proxy daemon";

    package = lib.mkPackageOption pkgs "vey-proxy" { };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = format.type;
      };
      default = { };
      description = ''
        Configuration for vey-proxy, generated as YAML.
        Do not put secrets in these settings, as the generated file is world-readable in the Nix store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.vey-proxy = {
      description = "VEY proxy daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      confinement = {
        enable = true;
        binSh = null;
        packages = [ configFile ];
      };
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} --control-dir /run/vey-proxy --config-file ${configFile}";
        DynamicUser = true;
        RuntimeDirectory = "vey-proxy";
        RuntimeDirectoryMode = "0700";
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0077";
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        BindReadOnlyPaths = [
          configFile
          "/etc/ssl/certs"
          "-/etc/resolv.conf"
          "-/etc/hosts"
        ]
        ++ lib.optionals config.services.resolved.enable [
          "/run/systemd/resolve/stub-resolv.conf"
          "/run/systemd/resolve/resolv.conf"
        ];
      };
    };
  };
}
