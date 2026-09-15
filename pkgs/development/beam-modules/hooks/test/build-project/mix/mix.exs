defmodule BuildProbe.MixProject do
  use Mix.Project

  def project do
    [
      app: :build_probe,
      version: "0.1.0",
      releases: [probe: []],
      escript: [main_module: BuildProbe, name: "hook-probe"]
    ]
  end
end
