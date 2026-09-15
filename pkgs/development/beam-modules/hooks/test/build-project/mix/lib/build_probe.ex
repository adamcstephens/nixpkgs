defmodule BuildProbe do
  @message "message" |> File.read!() |> String.trim()

  def message, do: @message

  def main(args) do
    IO.puts("#{message()}: #{Enum.join(args, " ")}")
  end
end
