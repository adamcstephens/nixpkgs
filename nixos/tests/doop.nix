{ ... }:
{
  name = "doop";

  nodes.machine = { pkgs, ... }: {
    services.doop = {
      enable = true;
      settings = {
        BETTER_AUTH_SECRET = "nixos-test-doop-secret-not-for-production";
        BETTER_AUTH_URL = "http://localhost:4400";
      };
    };

    fonts.packages = [ pkgs.dejavu_fonts ];

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

    with subtest("Chromium subprocesses survive the syscall filter"):
        kernel_log = machine.succeed("journalctl --boot --dmesg --no-pager")
        assert not any(
            "type=1326" in line and 'comm="chromium"' in line
            for line in kernel_log.splitlines()
        ), kernel_log

    with subtest("Chromium keeps its renderer sandbox"):
        service_pid = machine.succeed("systemctl show doop.service --property=MainPID --value").strip()
        renderer_pid = machine.succeed("pgrep --full --oldest 'chromium --type=renderer'").strip()
        for namespace in ("user", "pid", "net"):
            service_ns = machine.succeed(f"readlink /proc/{service_pid}/ns/{namespace}")
            renderer_ns = machine.succeed(f"readlink /proc/{renderer_pid}/ns/{namespace}")
            assert service_ns != renderer_ns, namespace
        service_status = dict(
            line.split(":", 1)
            for line in machine.succeed(f"cat /proc/{service_pid}/status").splitlines()
        )
        renderer_status = dict(
            line.split(":", 1)
            for line in machine.succeed(f"cat /proc/{renderer_pid}/status").splitlines()
        )
        assert renderer_status["NoNewPrivs"].strip() == "1"
        assert int(renderer_status["CapEff"], 16) == 0
        assert int(renderer_status["Seccomp_filters"]) > int(service_status["Seccomp_filters"])
  '';
}
