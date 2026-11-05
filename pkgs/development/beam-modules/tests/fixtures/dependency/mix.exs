defmodule DependencyFixture.MixProject do
  use Mix.Project

  def project do
    [
      app: :dependency_fixture,
      version: "1.0.0",
      compilers: [String.to_atom(Macro.underscore(DependencyFixture))] ++ Mix.compilers(),
      deps: []
    ]
  end

  def application, do: []
end

defmodule Mix.Tasks.Compile.DependencyFixture do
  use Mix.Task.Compiler

  def run(_args) do
    unless System.get_env("ALLOW_DEPENDENCY_COMPILATION") == "1" do
      Mix.raise("dependency recompilation is forbidden by the integration fixture")
    end

    {:ok, []}
  end
end
