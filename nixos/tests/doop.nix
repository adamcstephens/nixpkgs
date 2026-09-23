{ ... }:
{
  name = "doop";

  nodes.machine = {
    services.doop = {
      enable = true;
      settings = {
        BETTER_AUTH_SECRET = "nixos-test-doop-secret-not-for-production";
        BETTER_AUTH_URL = "http://localhost:4400";
      };
    };

    virtualisation.memorySize = 2048;
  };

  testScript = ''
    import json
    from datetime import timedelta

    machine.wait_for_unit("doop.service")
    machine.wait_for_open_port(4400, timeout=timedelta(seconds=120))
    assert json.loads(machine.succeed("curl --fail --silent http://localhost:4400/healthz")) == {"ok": True}
    machine.succeed("curl --fail --silent http://localhost:4400/ > /dev/null")
  '';
}
