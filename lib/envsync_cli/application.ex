defmodule EnvsyncCli.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = []

    Supervisor.start_link(children, strategy: :one_for_one, name: EnvsyncCli.Supervisor)
  end
end
