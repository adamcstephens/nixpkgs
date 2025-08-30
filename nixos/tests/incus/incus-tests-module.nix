{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tests.incus;
in
{
  options.tests.incus = {
    package = lib.mkPackageOption pkgs "incus" { };

    preseed = lib.mkOption {
      description = "configuration provided to incus preseed. https://linuxcontainers.org/incus/docs/main/howto/initialize/#non-interactive-configuration";
      type = lib.types.submodule {
        freeformType = (pkgs.formats.json { }).type;
      };
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }:
          {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                default = name;
              };

              type = lib.mkOption {
                type = lib.types.enum [
                  "container"
                  "virtual-machine"
                ];

              };

              imageAlias = lib.mkOption {
                type = lib.types.str;
                description = "name of image when imported";
                default = "nixos/${name}/${config.type}";
              };

              nixosConfig = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
              };

              testScript = lib.mkOption {
                type = lib.types.str;
                description = "final script provided to test runner";
                readOnly = true;
              };
            };
            config =
              let
                releases = import ../../release.nix {
                  configuration = {
                    # Building documentation makes the test unnecessarily take a longer time:
                    documentation.enable = lib.mkForce false;
                    documentation.nixos.enable = lib.mkForce false;

                    environment.etc."nix/registry.json".text = lib.mkForce "{}";

                    # Arbitrary sysctl modification to ensure containers can update sysctl
                    boot.kernel.sysctl."net.ipv4.ip_forward" = "1";
                  }
                  // config.nixosConfig;
                };

                images = {
                  container = {
                    metadata =
                      releases.incusContainerMeta.${pkgs.stdenv.hostPlatform.system}
                      + "/tarball/nixos-image-lxc-*-${pkgs.stdenv.hostPlatform.system}.tar.xz";

                    root =
                      releases.incusContainerImage.${pkgs.stdenv.hostPlatform.system}
                      + "/nixos-lxc-image-${pkgs.stdenv.hostPlatform.system}.squashfs";
                  };

                  virtual-machine = {
                    metadata = releases.incusVirtualMachineImageMeta.${pkgs.stdenv.hostPlatform.system} + "/*/*.tar.xz";
                    root = releases.incusVirtualMachineImage.${pkgs.stdenv.hostPlatform.system} + "/nixos.qcow2";
                  };
                };

                root = images.${config.type}.root;
                metadata = images.${config.type}.metadata;
              in
              {

                testScript = # python
                ''
                  with subtest("${config.name}(${config.type}) image can be imported"):
                      server.succeed("incus image import ${metadata} ${root} --alias ${config.imageAlias}")


                  with subtest("${config.name}(${config.type}) can be launched and managed"):
                      instance_name = server.succeed("incus launch ${config.imageAlias} --quiet").split(":")[1].strip()
                      server.wait_for_instance(instance_name)


                  with subtest("${config.name}(${config.type}) CPU limits can be managed"):
                      server.set_instance_config(instance_name, "limits.cpu 1", restart=True)
                      server.wait_instance_exec_success(instance_name, "nproc | grep '^1$'", timeout=90)


                  with subtest("${config.name}(${config.type}) CPU limits can be hotplug changed"):
                      server.set_instance_config(instance_name, "limits.cpu 2")
                      server.wait_instance_exec_success(instance_name, "nproc | grep '^2$'", timeout=90)


                  with subtest("${config.name}(${config.type}) memory limits can be managed"):
                      server.set_instance_config(instance_name, "limits.memory 128MB", restart=True)
                      server.wait_instance_exec_success(instance_name, "grep 'MemTotal:[[:space:]]*125000 kB' /proc/meminfo", timeout=90)


                  with subtest("${config.name}(${config.type}) memory limits can be hotplug changed"):
                      server.set_instance_config(instance_name, "limits.memory 256MB")
                      server.wait_instance_exec_success(instance_name, "grep 'MemTotal:[[:space:]]*250000 kB' /proc/meminfo", timeout=90)

                  with subtest("${config.name}(${config.type}) incus-agent is started"):
                      server.succeed(f"incus exec {instance_name} systemctl is-active incus-agent")


                  with subtest("${config.name}(${config.type}) incus-agent has a valid path"):
                      server.succeed(f"incus exec {instance_name} -- bash -c 'true'")

                  with subtest("virtual-machine can successfully restart"):
                      server.succeed(f"incus restart {instance_name}")
                      server.wait_for_instance(instance_name)


                  # with subtest("virtual-machine can be created"):
                  #     server.succeed(f"incus create {alias} vm-{variant}1 --vm --config limits.memory=512MB --config security.secureboot=false")
                  #
                  #
                  # with subtest("virtual-machine software tpm can be configured"):
                  #     server.succeed(f"incus config device add vm-{variant}1 vtpm tpm path=/dev/tpm0")

                  with subtest("${config.name}(${config.type}) software tpm can be configured"):
                      server.succeed(f"incus config device add {instance_name} vtpm tpm path=/dev/tpm0 pathrm=/dev/tpmrm0")
                      server.succeed(f"incus exec {instance_name} -- test -e /dev/tpm0")
                      server.succeed(f"incus exec {instance_name} -- test -e /dev/tpmrm0")
                      server.succeed(f"incus config device remove {instance_name} vtpm")
                      server.fail(f"incus exec {instance_name} -- test -e /dev/tpm0")
                ''
                #
                # container specific
                #
                + (lib.optionalString (config.type == "container")
                  # python
                  ''


                    with subtest("${config.name}(${config.type}) lxc-generator compatibility"):
                        with subtest("${config.name}(${config.type}) -container generator configures plain container"):
                            # default container is plain
                            server.succeed("incus exec {instance_name} test -- -e /run/systemd/system/service.d/zzz-lxc-service.conf")

                            server.check_instance_sysctl(instance_name)

                        with subtest("${config.name}(${config.type}) -container generator configures nested container"):
                            server.set_instance_config(instance_name, "security.nesting=true", restart=True)

                            server.fail(f"incus exec {instance_name} test -- -e /run/systemd/system/service.d/zzz-lxc-service.conf")
                            target = server.succeed(f"incus exec {instance_name} readlink -- -f /run/systemd/system/systemd-binfmt.service").strip()
                            assert target == "/dev/null", "lxc generator did not correctly mask /run/systemd/system/systemd-binfmt.service"

                            server.check_instance_sysctl(instance_name)

                        with subtest("${config.name}(${config.type}) -container generator configures privileged container"):
                            # Create a new instance for a clean state
                            instance_name2 = server.succeed("incus launch ${config.imageAlias} --quiet").split(":")[1].strip()
                            server.wait_for_instance(instance_name2)

                            server.succeed(f"incus exec {instance_name2} test -- -e /run/systemd/system/service.d/zzz-lxc-service.conf")

                            server.check_instance_sysctl(instance_name2)
                            server.exec(f"incus stop -f {instance_name2}")


                    with subtest("${config.name}(${config.type}) lxcfs"):
                        with subtest("${config.name}(${config.type}) mounts lxcfs overlays"):
                            server.succeed(f"incus exec {instance_name} mount | grep 'lxcfs on /proc/cpuinfo type fuse.lxcfs'")
                            server.succeed(f"incus exec {instance_name} mount | grep 'lxcfs on /proc/meminfo type fuse.lxcfs'")


                        with subtest("${config.name}(${config.type}) supports per-instance lxcfs"):
                            server.succeed(f"incus stop {instance_name}")
                            server.fail(f"pgrep -a lxcfs | grep 'incus/devices/{instance_name}/lxcfs'")

                            server.succeed("incus config set instances.lxcfs.per_instance=true")

                            server.succeed(f"incus start {instance_name}")
                            server.wait_for_instance(instance_name)
                            server.succeed(f"pgrep -a lxcfs | grep 'incus/devices/{instance_name}/lxcfs'")
                  ''
                )
                +
                  #
                  # finalize
                  #
                  # python
                  ''

                    with subtest("${config.name}(${config.type}) can successfully restart"):
                        server.succeed(f"incus restart {instance_name}")
                        server.wait_for_instance(instance_name)


                    with subtest("${config.name}(${config.type}) remains running when softDaemonRestart is enabled and service is stopped"):
                        pid = server.succeed(f"incus info {instance_name} | grep 'PID'").split(":")[1].strip()
                        server.succeed(f"ps {pid}")
                        server.succeed("systemctl stop incus")
                        server.succeed(f"ps {pid}")
                        server.succeed("systemctl start incus")

                        with subtest("${config.name}(${config.type}) stop with incus-startup.service"):
                            pid = server.succeed(f"incus info {instance_name} | grep 'PID'").split(":")[1].strip()
                            server.succeed(f"ps {pid}")
                            server.succeed("systemctl stop incus-startup.service")
                            server.wait_until_fails(f"ps {pid}", timeout=120)
                            server.succeed("systemctl start incus-startup.service")


                    server.exec(f"incus stop --force {instance_name2}")
                  '';

              };
          }
        )
      );
      description = "";
      default = { };
    };

    # all = lib.mkEnableOption "All tests";
    # init = {
    #   legacy = lib.mkEnableOption "Validate non-systemd init";
    #   systemd = lib.mkEnableOption "Validate systemd init";
    # };
    #
    # instance = {
    #   container = lib.mkEnableOption "Validate container functionality";
    #   virtual-machine = lib.mkEnableOption "Validate virtual machine functionality";
    # };
    #

    feature.user = lib.mkEnableOption "Validate incus user access feature";

    appArmor = lib.mkEnableOption "AppArmor during tests";

    network.ovs = lib.mkEnableOption "Validate OVS network integration";

    storage = {
      lvm = lib.mkEnableOption "Validate LVM storage integration";
      zfs = lib.mkEnableOption "Validate ZFS storage integration";
    };
  };

  config = {
    tests.incus = { };
  };
}
