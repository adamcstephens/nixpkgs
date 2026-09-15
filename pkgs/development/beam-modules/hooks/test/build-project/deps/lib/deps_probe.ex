defmodule DepsProbe do
  def message, do: "compiled with #{LocalProbe.message()}"
end
