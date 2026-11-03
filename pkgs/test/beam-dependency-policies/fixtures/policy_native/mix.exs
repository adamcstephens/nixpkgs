defmodule Mix.Tasks.Compile.PolicyNative do
  use Mix.Task.Compiler

  def run(_args) do
    {output, status} = System.cmd("bash", ["check-policy.sh"], stderr_to_stdout: true)
    IO.write(output)

    if status != 0, do: Mix.raise("Native policy fixture failed")
    {:ok, []}
  end
end

defmodule PolicyNative.MixProject do
  use Mix.Project

  def project do
    [
      app: :policy_native,
      version: "0.1.0",
      compilers: [:policy_native] ++ Mix.compilers()
    ]
  end
end
