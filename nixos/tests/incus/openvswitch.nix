import ../make-test-python.nix (
  { pkgs, lib, ... }:

  {
    name = "incus-openvswitch";

    meta = {
      maintainers = lib.teams.lxc.members;
    };

    nodes.machine =
      { lib, ... }:
      {
        networking.vswitches = {
          br0 = {
            interfaces = {
              eth0 = { };
            };
          };
        };
        networking.interfaces.vmbr0.useDHCP = true;

        virtualisation = {
          incus.enable = true;

          incus.preseed = {
            networks = [
              {
                name = "ovstestbr0";
                type = "bridge";
                config = {
                  "bridge.driver" = "openvswitch";
                  "ipv4.address" = "10.0.100.1/24";
                  "ipv4.nat" = "true";
                };
              }
            ];
            profiles = [
              {
                name = "nixostest_default";
                devices = {
                  eth0 = {
                    name = "eth0";
                    network = "ovstestbr0";
                    type = "nic";
                  };
                  root = {
                    path = "/";
                    pool = "default";
                    size = "35GiB";
                    type = "disk";
                  };
                };
              }
            ];
            storage_pools = [
              {
                name = "nixostest_pool";
                driver = "dir";
              }
            ];
          };

          vswitch.enable = true;
        };
      };

    testScript = ''
      machine.wait_for_unit("incus.service")
      machine.wait_for_unit("ovsdb.service")
      machine.wait_for_unit("incus-preseed.service")

    '';
  }
)
