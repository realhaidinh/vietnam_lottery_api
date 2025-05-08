defmodule LotteryApi.Scraper.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @regions [
    {:mb, 18, "https://az24.vn/xsmb-sxmb-xo-so-mien-bac.html"},
    {:mt, 17, "https://az24.vn/xsmt-sxmt-xo-so-mien-trung.html"},
    {:mn, 16, "https://az24.vn/xsmn-sxmn-xo-so-mien-nam.html"}
  ]

  @impl true
  def init(_init_arg) do
    children =
      Enum.map(@regions, fn {region, begin_at, url} ->
        state = %{region: region, begin_at: begin_at, url: url}
        Supervisor.child_spec({LotteryApi.Scraper.AZ24, state}, id: region)
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
