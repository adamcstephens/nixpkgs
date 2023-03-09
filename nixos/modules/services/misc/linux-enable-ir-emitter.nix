{ config
, lib
, pkgs
, ...
}:
with lib; let
  cfg = config.services.linux-enable-ir-emitter;
in
{
  options = {
    services.linux-enable-ir-emitter = {
      enable = mkEnableOption (mdDoc "") // {
        description = mdDoc ''
          Whether to enable IR emitter hardware. Designed to be used with the
          Howdy facial authentication. After enabling the service, configure
          the emitter with `sudo linux-enable-ir-emitter configure`.
        '';
      };

      package = mkPackageOptionMD pkgs "linux-enable-ir-emitter" {} // {
        description = mdDoc ''
          Package to use for the Linux Enable IR Emitter service.
        '';
      };

      device = mkOption {
        type = types.str;
        default = "video2";
        description = mdDoc ''
          IR camera device to depend on. For example, for `/dev/video2`
          the value would be `video2`. Find this with the command
          {command}`realpath /dev/v4l/by-path/<generated-driver-name>`.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # https://github.com/EmixamPP/linux-enable-ir-emitter/blob/7e3a6527ef2efccabaeefc5a93c792628325a8db/sources/systemd/linux-enable-ir-emitter.service
    systemd.services.linux-enable-ir-emitter = rec {
      description = "Enable the infrared emitter";
      script = "${getExe cfg.package} run";

      wantedBy = [
        "multi-user.target"
        "suspend.target"
        "hybrid-sleep.target"
        "hibernate.target"
        "suspend-then-hibernate.target"
      ];
      after = wantedBy ++ [ "dev-${cfg.device}.device" ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/linux-enable-ir-emitter 0755 root root - -"
    ];
    environment.etc."linux-enable-ir-emitter".source = "/var/lib/linux-enable-ir-emitter";
  };
}
