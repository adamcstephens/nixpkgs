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
    import base64
    import json
    from datetime import timedelta
    import shlex
    import struct

    machine.wait_for_unit("doop.service")
    machine.wait_for_open_port(4400, timeout=timedelta(seconds=120))
    assert json.loads(machine.succeed("curl --fail --silent http://localhost:4400/healthz")) == {"ok": True}
    machine.succeed("curl --fail --silent http://localhost:4400/ > /dev/null")

    def post(path, body):
        return json.loads(machine.succeed(
            "curl --fail-with-body --silent --show-error "
            "--cookie /tmp/doop.cookies --cookie-jar /tmp/doop.cookies "
            "--header 'Origin: http://localhost:4400' "
            f"--json {shlex.quote(json.dumps(body))} http://localhost:4400{path}"
        ))

    with subtest("Puppeteer renders a frame inside the doop service"):
        post("/api/auth/sign-up/email", {
            "name": "NixOS test",
            "email": "test@example.com",
            "password": "doop-test-password",
        })
        canvas = post("/api/canvases", {"name": "Browser regression"})
        frame = post(f"/api/canvases/{canvas['id']}/frames", {
            "name": "Chromium test",
            "width": 320,
            "height": 200,
            "html": "<!doctype html><html><body style='background: lime'>Doop Chromium test</body></html>",
        })
        status, _ = machine.execute(
            "curl --fail-with-body --silent --show-error --max-time 60 "
            "--cookie /tmp/doop.cookies --output /tmp/frame.png "
            f"http://localhost:4400/api/frames/{frame['id']}/screenshot.png"
        )
        assert status == 0, machine.succeed("cat /tmp/frame.png")
        png = base64.b64decode(machine.succeed("base64 --wrap=0 /tmp/frame.png"))
        assert png[:8] == b"\x89PNG\r\n\x1a\n"
        assert struct.unpack(">II", png[16:24]) == (320, 200)
        machine.copy_from_machine("/tmp/frame.png")
  '';
}
