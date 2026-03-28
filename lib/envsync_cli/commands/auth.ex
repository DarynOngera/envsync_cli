defmodule EnvsyncCli.Commands.Auth do
  alias EnvsyncCli.Auth

  def run(["login"],  _opts), do: Auth.login()
  def run(["logout"], _opts), do: Auth.logout()
  def run([], _opts),         do: Auth.login()
end
