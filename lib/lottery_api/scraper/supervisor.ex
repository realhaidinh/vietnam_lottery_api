defmodule LotteryApi.Scraper.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @regions [
    {:mb, 18},
    {:mt, 17},
    {:mn, 16}
  ]

  @impl true
  def init(_init_arg) do
    children =
      Enum.map(@regions, fn {region, begin_at} ->
        state = %{region: region, begin_at: begin_at}
        Supervisor.child_spec({LotteryApi.Scraper.AZ24, state}, id: region)
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
