defmodule SetupConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :setup_consumer,
      version: "1.0.0",
      deps: [{:setup_dep, path: "deps/setup_dep"}]
    ]
  end
end
