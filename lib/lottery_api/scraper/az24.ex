defmodule LotteryApi.Scraper.AZ24 do
  require Logger
  use GenServer
  alias LotteryApi.{Cache, Parser}

  @timezone "Asia/Saigon"

  def start_link(%{region: region} = state) do
    GenServer.start_link(__MODULE__, state, name: region)
  end

  @impl true
  def init(state) do
    {:ok, state, {:continue, :scraping}}
  end

  @impl true
  def handle_continue(:scraping, %{region: region, url: url, begin_at: begin_at} = state) do
    region_prizes = get_region_prize(region, url)
    Cache.insert({region, region_prizes})
    schedule_work(begin_at)
    {:noreply, state}
  end

  @impl true
  def handle_info(:scraping, %{region: region, url: url, begin_at: begin_at} = state) do
    schedule_work(begin_at)

    Task.start(fn ->
      region_prizes = get_region_prize(region, url)
      Cache.update(region, {2, region_prizes})
    end)

    {:noreply, state}
  end

  defp schedule_work(begin_at) do
    interval = get_interval(begin_at)
    Process.send_after(self(), :scraping, interval)
  end

  defp get_region_prize(region, url) do
    with {:http, {:ok, %{body: body}}} <- {:http, Req.get(url)},
         {:parse, {:ok, document}} <- Parser.parse_page(body, url) do
      prizes_table = Parser.parse_prizes_table(document)
      prizes = Parser.parse_prizes(prizes_table, region)
      date = Parser.parse_date(document)
      result = %{date: date}

      if region == :mb do
        Map.put(result, :prizes, prizes)
      else
        provinces =
          Parser.parse_provinces(prizes_table)
          |> Parser.update_provinces_prizes(prizes)

        Map.put(result, :provinces, provinces)
      end
    else
      {:http, {:error, error}} ->
        Logger.warning("Failed to scrape #{url}, because #{error}")
        %{}

      {:parse, {:error, error}} ->
        Logger.warning("Failed to parse #{url}, because #{error}")
        %{}
    end
  end

  defp get_interval(begin_at) do
    now = DateTime.now!(@timezone)

    start_time = %DateTime{now | hour: begin_at, minute: 15, second: 0}
    end_time = %DateTime{start_time | minute: 35, second: 0}

    cond do
      DateTime.before?(now, start_time) ->
        DateTime.diff(start_time, now, :millisecond)

      DateTime.after?(now, end_time) ->
        DateTime.add(start_time, 1, :day)
        |> DateTime.diff(now, :millisecond)

      true ->
        :timer.seconds(10)
    end
  end
end
