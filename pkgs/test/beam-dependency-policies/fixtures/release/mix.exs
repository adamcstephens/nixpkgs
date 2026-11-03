defmodule PolicyRelease.MixProject do
  use Mix.Project

  def project do
    [
      app: :policy_release,
      version: "0.1.0",
      deps: deps(),
      releases: [policy_release: [include_erts: false]]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    case System.get_env("BEAM_POLICY_TEST_DEPS", "ca") do
      "ca" ->
        [
          {:castore, "== 0.1.0"},
          {:certifi, "== 0.1.0", manager: :rebar3}
        ]

      "native" ->
        [{:policy_native, "== 0.1.0"}]

      "empty" ->
        []
    end
  end
end
