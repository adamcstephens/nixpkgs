defmodule RootFixture.MixProject do
  use Mix.Project

  def project do
    [
      app: :root_fixture,
      version: "1.0.0",
      deps: [
        {:jason, "~> 1.4"},
        {:telemetry, "~> 1.4"},
        {:git_fixture, git: "@git_url@", branch: "main"},
        {:path_fixture, path: "@path_source@"},
        {:editable_fixture, path: "@editable_source@"}
      ]
    ]
  end

  def application, do: []
end

defmodule Mix.Tasks.SubprocessFixture do
  use Mix.Task

  def run(_args) do
    {output, status} =
      System.cmd("mix", ["run", "--no-start", "-e", "RootFixture.assert_dependencies!()"],
        stderr_to_stdout: true
      )

    IO.write(output)

    if status != 0 do
      Mix.raise("subprocess mix failed with status #{status}")
    end

    {_output, 23} =
      System.cmd("mix", ["run", "--no-start", "-e", "System.halt(23)"], stderr_to_stdout: true)
  end
end
