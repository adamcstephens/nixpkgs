import ../make-test-python.nix ({ pkgs, lib, ... } :

let
  lxd-image = import ../../release.nix {
    configuration = {
      # Building documentation makes the test unnecessarily take a longer time:
      documentation.enable = lib.mkForce false;

      # Our tests require `grep` & friends:
      environment.systemPackages = with pkgs; [ busybox ];
    };
  };

  lxd-image-metadata = lxd-image.lxdVirtualMachineImageMeta.${pkgs.stdenv.hostPlatform.system};
  lxd-image-disk = lxd-image.lxdVirtualMachineImage.${pkgs.stdenv.hostPlatform.system};

  instance-name = "instance1";
in {
  name = "lxd-virtual-machine";

  meta = with pkgs.lib.maintainers; {
    maintainers = [ adamcstephens ];
  };

  nodes.machine = { lib, ... }: {
    virtualisation = {
      diskSize = 4096;

      cores = 2;

      # Since we're testing nested virtual machines, we need enough memory
      memorySize = 1024;

      lxc.lxcfs.enable = true;
      lxd.enable = true;
    };
  };

  testScript = ''
    def instance_is_up(_) -> bool:
      status, _ = machine.execute("lxc exec ${instance-name} --disable-stdin --force-interactive /run/current-system/sw/bin/true")
      return status == 0

    machine.wait_for_unit("sockets.target")
    machine.wait_for_unit("lxd.service")
    machine.wait_for_file("/var/lib/lxd/unix.socket")

    # Wait for lxd to settle
    machine.succeed("lxd waitready")

    machine.succeed("lxd init --minimal")

    machine.succeed(
        "lxc image import ${lxd-image-metadata}/*/*.tar.xz ${lxd-image-disk}/nixos.qcow2 --alias nixos"
    )

    with subtest("Container can be managed"):
        machine.succeed("lxc launch nixos ${instance-name} --vm --config limits.memory=512MB")
        with machine.nested("Waiting for instance to start and be usable"):
          retry(instance_is_up)
  '';
})
