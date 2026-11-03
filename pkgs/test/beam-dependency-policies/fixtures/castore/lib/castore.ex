defmodule CAStore do
  @certificates File.read!("priv/cacerts.pem")

  def certificates, do: @certificates
end
