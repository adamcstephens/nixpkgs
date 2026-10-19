{ pkgs, ... }:

{
  name = "vey-proxy";

  nodes.machine = {

    services.vey-proxy = {
      enable = true;
      settings = {
        runtime.thread_number = 1;
        controller.local = { };
        server = [
          {
            name = "default";
            type = "http_proxy";
            escaper = "default";
            listen.address = "127.0.0.1:18080";
          }
        ];
        resolver = [
          {
            name = "default";
            type = "c-ares";
          }
        ];
        escaper = [
          {
            name = "default";
            type = "DirectFixed";
            resolver = "default";
          }
        ];
      };
    };

    services.httpd.enable = true;
    services.httpd.adminAddr = "test@example.org";
    services.httpd.virtualHosts."example.test".documentRoot =
      pkgs.writeTextDir "index.html" "vey-proxy-ok";
  };

  testScript = ''
    machine.wait_for_unit("vey-proxy.service")
    machine.wait_for_open_port(18080)
    machine.wait_for_unit("httpd.service")
    assert machine.succeed("curl --fail --noproxy \"\" --proxy http://127.0.0.1:18080 http://192.168.1.1/ --header 'Host: example.test'") == "vey-proxy-ok"
    pid = machine.succeed("systemctl show vey-proxy.service --property=MainPID --value").strip()
    machine.succeed(f"test -d /proc/{pid}/root/run/vey-proxy")
    machine.fail(f"test -e /proc/{pid}/root/etc/shadow")
  '';
}
