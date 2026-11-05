defmodule UmbrellaPeer.MixProject do
  use Mix.Project

  def project do
    [app: :umbrella_peer, version: "1.0.0", deps: [{:path_fixture, in_umbrella: true}]]
  end
end
