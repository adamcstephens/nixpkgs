{
  cacert,
  pkg-config,
  vips,
  glib,
}:

let
  caBundlePolicy = {
    sourcePatch = ''
      cp ${cacert}/etc/ssl/certs/ca-bundle.crt priv/cacerts.pem
    '';
  };
in
{
  castore = caBundlePolicy;
  certifi = caBundlePolicy;

  vix = {
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [
      vips
      glib.dev
    ];
    env.VIX_COMPILATION_MODE = "PLATFORM_PROVIDED_LIBVIPS";
  };
}
