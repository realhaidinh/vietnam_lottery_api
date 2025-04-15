defmodule LotteryApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: LotteryApi.Worker.start_link(arg)
      # {LotteryApi.Worker, arg}
      {Bandit, plug: LotteryApi.Router}
    ]
    children = children ++ get_children()
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LotteryApi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_children do
    regions = [:mb, :mt, :mn]
    Enum.map(regions, fn region ->
      Supervisor.child_spec({LotteryApi.Scraper, region}, id: region)
    end)
  end
end
