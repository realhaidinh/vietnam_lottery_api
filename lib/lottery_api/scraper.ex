defmodule LotteryApi.Scraper do
  require Logger
  use GenServer

  @prizes_table :prizes_table

  def start_link(region) do
    GenServer.start_link(__MODULE__, region, name: region)
  end

  def get_region_prizes(region) do
    [{^region, region_prizes}] = :ets.lookup(@prizes_table, region)
    region_prizes
  end

  @impl true
  def init(region) do
    opts = [:set, :public, :named_table, read_concurrency: true, write_concurrency: true]

    case :ets.whereis(@prizes_table) do
      :undefined -> :ets.new(@prizes_table, opts)
      _ -> nil
    end

    {:ok, region, {:continue, :scraping}}
  end

  @impl true
  def handle_continue(:scraping, region) do
    region_prizes = fetch_region_prize(region)
    :ets.insert(@prizes_table, {region, region_prizes})
    Process.send_after(self(), :scraping, get_interval(region))
    {:noreply, region}
  end

  @impl true
  def handle_info(:scraping, region) do
    Process.send_after(self(), :scraping, get_interval(region))

    Task.start(fn ->
      region_prizes = fetch_region_prize(region)
      GenServer.cast(__MODULE__, {:scraped, region_prizes})
    end)

    {:noreply, region}
  end

  @impl true
  def handle_cast({:scraped, region_prizes}, region) do
    :ets.update_element(@prizes_table, region, region_prizes)
    {:noreply, region}
  end

  defp fetch_region_prize(region) do
    url = get_url(region)
    scraper_fun = get_scraper_fun(region)
    scrape_page(url, scraper_fun)
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
      result = %{date: get_date(document)}

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

  defp get_date(document) do
    href =
      document
      |> Floki.find("div.tit-mien")
      |> List.first()
      |> Floki.find("a:nth-child(3)")
      |> Floki.attribute("href")
      |> List.first()

    <<_::binary-21, date::binary-size(byte_size(href) - 26), _::binary-5>> = href
    date
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
          :mb -> format_tier(tier)
          _ -> tier
        end
      end,
      fn {_, _, element} ->
        case element do
          [{_, _, [number]}] -> number
          [number] -> number
          list -> Enum.join(list)
        end
      end
    )
  end

  defp get_citites(prizes_table) do
    prizes_table
    |> Floki.find("th > a")
    |> Enum.map(&%{name: Floki.text(&1), prizes: %{}})
  end

  defp update_cities_prizes(cities, prizes) do
    Enum.reduce(prizes, cities, fn {tier, numbers}, prev_cities ->
      formatted_tier = format_tier(tier)

      Enum.zip_with(prev_cities, numbers, fn city, number ->
        number =
          cond do
            String.ends_with?(tier, ["imgloadig", "cl-rl"]) -> "Đang xổ số"
            true -> number
          end

        update_in(city[:prizes][formatted_tier], fn
          nil -> [number]
          prizes -> [number | prizes]
        end)
      end)
    end)
  end

  defp format_tier(tier) do
    tier
    |> String.trim()
    |> String.split(["-", " "])
    |> Enum.at(1)
    |> String.upcase()
  end

  defp get_url(:mb), do: "https://az24.vn/xsmb-sxmb-xo-so-mien-bac.html"
  defp get_url(:mn), do: "https://az24.vn/xsmn-sxmn-xo-so-mien-nam.html"
  defp get_url(:mt), do: "https://az24.vn/xsmt-sxmt-xo-so-mien-trung.html"

  @timezone "Asia/Saigon"
  defp get_interval(region) do
    now = DateTime.now!(@timezone)

    hour = get_region_hour(region)

    start_time = %DateTime{now | hour: hour, minute: 15, second: 0}
    end_time = %DateTime{now | hour: hour, minute: 35, second: 0}

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

  def get_region_hour(:mb), do: 18
  def get_region_hour(:mt), do: 17
  def get_region_hour(:mn), do: 16
end
