{
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./lxd-instance-common.nix
  ];

  options = {
    virtualisation.lxd = {
      privilegedContainer = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc ''
          Whether this LXD container will be running as a privileged container or not. If set to `true` then
          additional configuration will be applied to the `systemd` instance running within the container as
          recommended by [distrobuilder](https://linuxcontainers.org/distrobuilder/introduction/).
        '';
      };
    };
  };

  config = {
    boot.isContainer = true;

    boot.postBootCommands = ''
      # After booting, register the contents of the Nix store in the Nix
      # database.
      if [ -f /nix-path-registration ]; then
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration &&
        rm /nix-path-registration
      fi

      # nixos-rebuild also requires a "system" profile
      ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
    '';

    # TODO: build rootfs as squashfs for faster unpack
    system.build.tarball = pkgs.callPackage ../../lib/make-system-tarball.nix {
      extraArgs = "--owner=0";

      storeContents = [
        {
          object = config.system.build.toplevel;
          symlink = "none";
        }
      ];

      contents = [
        {
          source = config.system.build.toplevel + "/init";
          target = "/sbin/init";
        }
        {
          source = config.system.build.toplevel + "/etc/os-release";
          target = "/etc/os-release";
        }
      ];

      extraCommands = "mkdir -p proc sys dev";
    };

    system.activationScripts.installInitScript = lib.mkForce ''
      ln -fs $systemConfig/init /sbin/init
    '';

    # create systemd generator to allow for dynamically configuring the systemd environment based on container configuration
    systemd.generators = let
      generator = pkgs.writeText "lxd" ''
        #!/run/current-system/sw/bin/bash

        set -eu

        # disable localisation (faster grep)
        export LC_ALL=C

        ## Helper functions
        # is_lxc_container succeeds if we're running inside a LXC container
        is_lxc_container() {
            grep -qa container=lxc /proc/1/environ
        }

        is_lxc_privileged_container() {
            grep -qw 4294967295$ /proc/self/uid_map
        }

        # is_lxd_vm succeeds if we're running inside a LXD VM
        is_lxd_vm() {
            [ -e /dev/virtio-ports/org.linuxcontainers.lxd ]
        }

        ## Fix functions
        # fix_ro_paths avoids udevd issues with /sys and /proc being writable
        fix_ro_paths() {
            mkdir -p "/run/systemd/system/$1.d"
            cat <<-EOF >"/run/systemd/system/$1.d/zzz-lxc-ropath.conf"
        [Service]
        BindReadOnlyPaths=/sys /proc
        EOF
        }

        # fix_systemd_override_unit generates a unit specific override
        fix_systemd_override_unit() {
            dropin_dir="/run/systemd/$1.d"
            mkdir -p "$dropin_dir"
            {
                echo "[Service]"
                [ "$systemd_version" -ge 247 ] && echo "ProcSubset=all"
                [ "$systemd_version" -ge 247 ] && echo "ProtectProc=default"
                [ "$systemd_version" -ge 232 ] && echo "ProtectControlGroups=no"
                [ "$systemd_version" -ge 232 ] && echo "ProtectKernelTunables=no"
                [ "$systemd_version" -ge 239 ] && echo "NoNewPrivileges=no"
                [ "$systemd_version" -ge 249 ] && echo "LoadCredential="
                [ "$systemd_version" -ge 254 ] && echo "PrivateNetwork=no"

                # Additional settings for privileged containers
                if is_lxc_privileged_container; then
                    echo "ProtectHome=no"
                    echo "ProtectSystem=no"
                    echo "PrivateDevices=no"
                    echo "PrivateTmp=no"
                    [ "$systemd_version" -ge 244 ] && echo "ProtectKernelLogs=no"
                    [ "$systemd_version" -ge 232 ] && echo "ProtectKernelModules=no"
                    [ "$systemd_version" -ge 231 ] && echo "ReadWritePaths="
                    [ "$systemd_version" -ge 254 ] && echo "ImportCredential="
                fi

                true
            } >"$dropin_dir/zzz-lxc-service.conf"
        }

        # fix_systemd_mask masks the systemd unit
        fix_systemd_mask() {
            ln -sf /dev/null "/run/systemd/system/$1"
        }

        # fix_systemd_udev_trigger overrides the systemd-udev-trigger.service to match the latest version
        # of the file which uses "ExecStart=-" instead of "ExecStart=".
        fix_systemd_udev_trigger() {
            cmd=
            if [ -f /usr/bin/udevadm ]; then
                cmd=/usr/bin/udevadm
            elif [ -f /sbin/udevadm ]; then
                cmd=/sbin/udevadm
            elif [ -f /bin/udevadm ]; then
                cmd=/bin/udevadm
            else
                return 0
            fi

            mkdir -p /run/systemd/system/systemd-udev-trigger.service.d
            cat <<-EOF >/run/systemd/system/systemd-udev-trigger.service.d/zzz-lxc-override.conf
        [Service]
        ExecStart=
        ExecStart=-/run/current-system/sw/bin/udevadm trigger --type=subsystems --action=add
        ExecStart=-/run/current-system/sw/bin/udevadm trigger --type=devices --action=add
        EOF
        }

        # fix_systemd_sysctl overrides the systemd-sysctl.service to use "ExecStart=-" instead of "ExecStart=".
        fix_systemd_sysctl() {
            mkdir -p /run/systemd/system/systemd-sysctl.service.d
            cat <<-EOF >/run/systemd/system/systemd-sysctl.service.d/zzz-lxc-override.conf
        [Service]
        ExecStart=
        ExecStart=-/run/current-system/sw/lib/systemd/systemd-sysctl
        EOF
        }

        ## Main logic
        # Nothing to do in LXD VM but deployed in case it is later converted to a container
        is_lxd_vm && exit 0

        # Exit immediately if not a LXC/LXD container
        is_lxc_container || exit 0

        # Check for NetworkManager
        nm_exists=0

        is_in_path NetworkManager && nm_exists=1

        # Determine systemd version
        systemd_version="$(/run/current-system/sw/lib/systemd/systemd --version | head -n1 | cut -d' ' -f2)"

        # Overriding some systemd features is only needed if security.nesting=false
        # in which case, /dev/.lxc will be missing
        if [ ! -d /dev/.lxc ]; then
            # Apply systemd overrides
            fix_systemd_override_unit system/service

            # Workarounds for privileged containers.
            if ! is_lxc_privileged_container; then
                fix_ro_paths systemd-networkd.service
                fix_ro_paths systemd-resolved.service
            fi
        fi

        # Ignore failures on some units.
        fix_systemd_udev_trigger
        fix_systemd_sysctl

        # Mask some units.
        fix_systemd_mask dev-hugepages.mount
        fix_systemd_mask run-ribchester-general.mount
        fix_systemd_mask systemd-hwdb-update.service
        fix_systemd_mask systemd-journald-audit.socket
        fix_systemd_mask systemd-modules-load.service
        fix_systemd_mask systemd-pstore.service
        fix_systemd_mask ua-messaging.service
        fix_systemd_mask systemd-firstboot.service
        fix_systemd_mask systemd-binfmt.service
        if [ ! -e /dev/tty1 ]; then
            fix_systemd_mask vconsole-setup-kludge@tty1.service
        fi

        mkdir -p /run/udev/rules.d
        cat <<-EOF >/run/udev/rules.d/90-lxc-net.rules
        # This file was created by distrobuilder.
        #
        # Its purpose is to convince NetworkManager to treat the eth0 veth
        # interface like a regular Ethernet. NetworkManager ordinarily doesn't
        # like to manage the veth interfaces, because they are typically configured
        # by container management tooling for specialized purposes.

        ACTION=="add|change|move", ENV{ID_NET_DRIVER}=="veth", ENV{INTERFACE}=="eth[0-9]*", ENV{NM_UNMANAGED}="0"
        EOF

        # Workarounds for NetworkManager in containers
        if /run/current-system/sw/bin/systemctl is-enabled NetworkManager --quiet; then
            fix_nm_link_state eth0
        fi
      '';
    in {
      lxd = "${generator}";
    };
  };
}
