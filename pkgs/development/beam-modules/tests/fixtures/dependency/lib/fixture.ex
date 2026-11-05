defmodule DependencyFixture do
  @value Application.compile_env(:dependency_fixture, :value, :expected)

  def value, do: @value
end
