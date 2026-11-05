defmodule RootFixture do
  @path_value FixturePath.value()
  @git_value FixtureGit.value()

  def assert_dependencies! do
    :expected = @path_value
    :expected = @git_value
    :editable = FixtureEditable.value()
    %{"value" => "expected"} = Jason.decode!(Jason.encode!(%{value: :expected}))
    {:ok, _applications} = Application.ensure_all_started(:telemetry)
    :ok = :telemetry.execute([:precompiled, :fixture], %{value: 1}, %{})
    IO.puts("precompiled dependencies are available")
  end
end
