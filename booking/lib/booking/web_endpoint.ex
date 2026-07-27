defmodule Booking.WebEndpoint do
  @moduledoc """
  Arranca el listener HTTP/WebSocket (**Cowboy**, sobre **Ranch**) en el puerto de config
  (`:booking, :web_port`, default 4000). Rutea la ruta `"/ws"` al handler
  `Booking.WebSocketHandler`.

  Va **último** en el árbol de supervisión: solo aceptamos conexiones con el dominio
  (Persistence / Registry / FlightSupervisor) ya arriba. Se embebe como *child spec* de
  Ranch (equivalente a `:cowboy.start_clear/3`), para que viva bajo nuestro árbol.
  """
  @listener :booking_http

  def child_spec(_opts) do
    port = Application.get_env(:booking, :web_port, 4000)

    dispatch =
      :cowboy_router.compile([
        {:_, [{"/ws", Booking.WebSocketHandler, []}]}
      ])

      :ranch.child_spec(
      @listener,
      :ranch_tcp,
      %{socket_opts: [port: port]},
      :cowboy_clear,
      %{env: %{dispatch: dispatch}}
    )
  end
end
