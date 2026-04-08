defmodule EnvsyncCli.Commands.Auth do
  alias EnvsyncCli.Auth

  def run(["login"], opts), do: Auth.login(Keyword.get(opts, :provider, "github"))
  def run(["logout"], _opts), do: Auth.logout()
  def run([], opts), do: Auth.login(Keyword.get(opts, :provider, "github"))
end
