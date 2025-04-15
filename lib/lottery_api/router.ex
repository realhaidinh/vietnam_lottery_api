defmodule LotteryApi.Router do
  use Plug.Router
  alias LotteryApi.Scraper

  plug(:match)
  plug(:dispatch)

  get "/api/:region" when region in ~w(xsmn xsmb xsmt) do
    body =
      region
      |> get_region()
      |> Scraper.get_region_prizes()
      |> JSON.encode_to_iodata!()

    conn = put_resp_content_type(conn, "application/json")
    send_resp(conn, 200, body)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp get_region("xsmb"), do: :mb
  defp get_region("xsmt"), do: :mt
  defp get_region("xsmn"), do: :mn

end
