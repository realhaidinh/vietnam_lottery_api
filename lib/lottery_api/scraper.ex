defmodule LotteryApi.Scraper do
  require Logger
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end
  @prizes_table :prizes_table
  @impl true
  def init(:ok) do
    opts = [:set, :protected, :named_table, read_concurrency: true, write_concurrency: true]
    prizes = :ets.new(@prizes_table, opts)
    {:ok, prizes, {:continue, :scraping}}
  end

  @impl true
  def handle_continue(:scraping, prizes) do
    regions = [:mb, :mn, :mt]
    for region_prizes <- get_prizes(regions) do
      :ets.insert(prizes, region_prizes)
    end
    {:noreply, prizes}
  end

  @impl true
  def handle_info({:scraping, region}, state) do
    Process.send_after(self(), {:scraping, region}, get_interval(region))

    Task.start(fn ->
      url = get_url(region)
      scraper_fun = get_scraper_fun(region)
      region_prizes = scrape_page(url, scraper_fun)
      GenServer.cast(__MODULE__, {:scraped, region, region_prizes})
    end)

    {:noreply, state}
  end


  @impl true
  def handle_cast({:scraped, region, region_prizes}, state) do
    :ets.update_element(state, region, region_prizes)
    {:noreply, state}
  end

  def get_region_prizes(region) do
    [{^region, region_prizes}] = :ets.lookup(@prizes_table, region)
    region_prizes
  end

  defp get_prizes(regions) do
    pid = self()

    stream =
      Task.async_stream(regions, fn region ->
        url = get_url(region)
        scraper_fun = get_scraper_fun(region)
        Process.send_after(pid, {:scraping, region}, get_interval(region))
        {region, scrape_page(url, scraper_fun)}
      end)

    Enum.into(stream, %{}, fn {:ok, {region, prizes}} -> {region, prizes} end)
  end

  def scrape_page(url, scraper_fun) do
    Logger.info("Scraping url: #{url}")
    opts = [attributes_as_maps: true]

    with {:http, {:ok, %{body: body}}} <- {:http, Req.get(url)},
         {:parse, {:ok, document}} <- {:parse, Floki.parse_document(body, opts)} do
      scraper_fun.(document)
    else
      {:http, {:error, error}} ->
        Logger.warning("Failed to get #{url}, because #{Exception.message(error)}")
        %{}

      {:parse, {:error, error}} ->
        Logger.warning("Failed to parse #{url}, because #{error}")
        %{}
    end
  end

  defp get_scraper_fun(region) do
    fn document ->
      prizes_table = get_prizes_table(document)
      prizes = get_prizes(prizes_table, region)
      result = %{date: get_current_date()}

      case region do
        :mb ->
          Map.put(result, :prizes, prizes)

        _ ->
          cities =
            get_citites(prizes_table)
            |> update_cities_prizes(prizes)

          Map.put(result, :cities, cities)
      end
    end
  end

  defp get_prizes_table(document) do
    document
    |> Floki.find("table:first-child")
    |> List.first()
  end

  defp get_prizes(prizes_table, region) do
    selector = if region == :mb, do: "td.v-giai > span[data-nc]", else: "td > div"

    prizes_table
    |> Floki.find(selector)
    |> Enum.group_by(
      fn {_, %{"class" => tier}, _} ->
        case region do
          :mb -> String.split(tier, "-") |> Enum.at(1) |> String.upcase()
          _ -> tier
        end
      end,
      &Enum.join(elem(&1, 2))
    )
  end

  defp get_citites(prizes_table) do
    prizes_table
    |> Floki.find("th > a")
    |> Enum.map(&%{name: Floki.text(&1), prizes: %{}})
  end

  defp update_cities_prizes(cities, prizes) do
    Enum.reduce(prizes, cities, fn {tier, numbers}, prev_cities ->
      tier = format_tier(tier)

      Enum.zip_with(prev_cities, numbers, fn city, number ->
        update_in(city[:prizes][tier], fn
          nil -> [number]
          prizes -> [number | prizes]
        end)
      end)
    end)
  end

  defp format_tier(tier) do
    tier
    |> String.trim()
    |> String.split("-")
    |> Enum.at(1)
    |> String.upcase()
  end

  @timezone "Asia/Saigon"
  defp get_current_date(), do: Calendar.strftime(DateTime.now!(@timezone), "%d-%m-%Y")

  defp get_url(region) do
    case region do
      :mb -> "https://az24.vn/xsmb-sxmb-xo-so-mien-bac.html"
      :mn -> "https://az24.vn/xsmn-sxmn-xo-so-mien-nam.html"
      :mt -> "https://az24.vn/xsmt-sxmt-xo-so-mien-trung.html"
    end
  end

  defp get_interval(region) do
    now = DateTime.now!(@timezone)

    hour =
      case region do
        :mb -> 18
        :mn -> 16
        :mt -> 17
      end

    start_time = %DateTime{now | hour: hour, minute: 15, second: 0}
    end_time = %DateTime{now | hour: hour, minute: 35, second: 0}

    cond do
      DateTime.before?(now, start_time) ->
        DateTime.diff(start_time, now, :millisecond)

      DateTime.after?(now, end_time) ->
        DateTime.add(start_time, 1, :day)
        |> DateTime.diff(now, :millisecond)

      true ->
        :timer.minutes(1)
    end
  end
end
