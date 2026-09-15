defmodule SetupProject do
  @message Application.compile_env(:setup_project, :message, :default)

  def message, do: @message
end
