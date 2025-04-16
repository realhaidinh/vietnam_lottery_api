defmodule LotteryApi.Scraper.AZ24 do
  require Logger
  use GenServer
  alias LotteryApi.Cache
  @timezone "Asia/Saigon"
  def start_link(%{region: region} = state) do
    GenServer.start_link(__MODULE__, state, name: region)
  end

  @impl true
  def init(state) do
    {:ok, state, {:continue, :scraping}}
  end

  @impl true
  def handle_continue(:scraping, %{region: region, begin_at: begin_at} = state) do
    url = get_region_url(region)
    state = Map.put(state, :url, url)
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
    with {:ok, document} <- parse_page(url) do
      prizes_table = get_prizes_table(document)
      prizes = get_prizes(prizes_table, region)
      date = get_date(document)
      result = %{date: date}

      case region do
        :mb ->
          Map.put(result, :prizes, prizes)

        _ ->
          provinces =
            get_provinces(prizes_table)
            |> update_provinces_prizes(prizes)

          Map.put(result, :provinces, provinces)
      end
    else
      {:error, _} -> %{}
    end
  end

  def parse_page(url) do
    Logger.info("Parsing page: #{url}")
    opts = [attributes_as_maps: true]

    with {:http, {:ok, %{body: body}}} <- {:http, Req.get(url)},
         {:parse, {:ok, document}} <- {:parse, Floki.parse_document(body, opts)} do
      {:ok, document}
    else
      {:http, {:error, error}} ->
        Logger.warning("Failed to get #{url}, because #{Exception.message(error)}")
        {:error, error}

      {:parse, {:error, error}} ->
        Logger.warning("Failed to parse #{url}, because #{error}")
        {:error, error}
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

  defp get_provinces(prizes_table) do
    prizes_table
    |> Floki.find("th > a")
    |> Enum.map(&%{name: Floki.text(&1), prizes: %{}})
  end

  defp update_provinces_prizes(provinces, prizes) do
    Enum.reduce(prizes, provinces, fn {tier, numbers}, prev_provinces ->
      formatted_tier = format_tier(tier)

      Enum.zip_with(prev_provinces, numbers, fn city, number ->
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

  defp get_region_url(:mb), do: "https://az24.vn/xsmb-sxmb-xo-so-mien-bac.html"
  defp get_region_url(:mn), do: "https://az24.vn/xsmn-sxmn-xo-so-mien-nam.html"
  defp get_region_url(:mt), do: "https://az24.vn/xsmt-sxmt-xo-so-mien-trung.html"

  defp get_interval(begin_at) do
    # :timer.seconds(10)
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
