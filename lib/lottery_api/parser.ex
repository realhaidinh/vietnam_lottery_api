defmodule LotteryApi.Parser do
  require Logger

  def parse_page(body, url) do
    Logger.info("Parsing page: #{url}")
    opts = [attributes_as_maps: true]

    case Floki.parse_document(body, opts) do
      {:ok, document} -> {:parse, {:ok, document}}
      {:error, error} -> {:parse, {:error, error}}
    end
  end

  def parse_date(document) do
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

  def parse_prizes_table(document) do
    document
    |> Floki.find("table:first-child")
    |> List.first()
  end

  def parse_prizes(prizes_table, region) do
    selector = if region == :mb, do: "td.v-giai > span[data-nc]", else: "td > div"

    prizes_table
    |> Floki.find(selector)
    |> Enum.group_by(
      fn {_, %{"class" => tier}, _} ->
        if region == :mb, do: format_tier(tier), else: tier
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

  def parse_provinces(prizes_table) do
    prizes_table
    |> Floki.find("th > a")
    |> Enum.map(&%{name: Floki.text(&1), prizes: %{}})
  end

  def update_provinces_prizes(provinces, prizes) do
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
end
