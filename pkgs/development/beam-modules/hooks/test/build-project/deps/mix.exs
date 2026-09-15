defmodule DepsProbe.MixProject do
  use Mix.Project

  def project do
    [
      app: :deps_probe,
      version: "0.1.0",
      deps: [{:local_probe, path: "local_probe"}]
    ]
  end
end
