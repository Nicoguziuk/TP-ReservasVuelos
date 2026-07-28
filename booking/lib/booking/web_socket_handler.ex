defmodule Booking.WebSocketHandler do
  @moduledoc """
  Handler WebSocket de Cowboy (`:cowboy_websocket`): **el proceso de conexión**. Cowboy/Ranch
  crea uno por cada conexión y llama a estos callbacks por nombre.

  Es **solo cáscara**: decodifica el JSON entrante, delega en `Booking.Protocol.handle/2` (la
  lógica testeable) y vuelve a codificar la respuesta. Su estado **es el contexto** de la
  conexión. Además gestiona la **suscripción** al vuelo abierto: al cambiar de vuelo
  (`open_flight`) suscribe/desuscribe; en `terminate` se desuscribe; y los broadcasts del
  `FlightServer` (`{:push, _}`) los empuja al navegador en `websocket_info`.
  """

  alias Booking.{FlightServer, FlightSupervisor, Persistence, Protocol}

  # Request HTTP entrante: le pedimos a Cowboy hacer el upgrade a WebSocket.
  def init(req, _opts) do
    websocket_opts = %{idle_timeout: 900_000}
    {:cowboy_websocket, req, nil, websocket_opts}
  end

  # Tras el handshake: armamos el contexto con los módulos reales del dominio.
  def websocket_init(_state) do
    context = %{
      user_id: nil,
      flight_id: nil,
      persistence: Persistence,
      lookup: &FlightSupervisor.lookup/1
    }

    {:ok, context}
  end

  # Frame de texto del cliente: parsear -> despachar -> responder (espejando `ref`).
  # El contexto devuelto por `Protocol.handle/2` reemplaza al actual. Si cambió el vuelo
  # abierto, se actualiza la suscripción.
  def websocket_handle({:text, text}, context) do
    {response, new_context} =
      case Jason.decode(text) do
        {:ok, message} ->
          {response, ctx} = Protocol.handle(message, context)
          {put_ref(response, message), ctx}

        {:error, _reason} ->
          {%{type: "error", reason: "invalid_message"}, context}
      end

    new_context = sync_subscription(context, new_context)
    {:reply, {:text, Jason.encode!(response)}, new_context}
  end

  # Otros frames (binario/ping/pong): los ignoramos por ahora.
  def websocket_handle(_frame, context) do
    {:ok, context}
  end

  # Broadcast del FlightServer: lo serializamos y lo empujamos al navegador.
  def websocket_info({:push, message}, context) do
    {:reply, {:text, Jason.encode!(message)}, context}
  end

  def websocket_info(_info, context) do
    {:ok, context}
  end

  # La conexión se cerró: desuscribir del vuelo que estuviera mirando.
  def terminate(_reason, _req, %{flight_id: flight_id}) do
    unsubscribe_flight(flight_id)
    :ok
  end

  def terminate(_reason, _req, _context), do: :ok

  # --- Auxiliares ---

  # Si `open_flight` cambió el vuelo, desuscribe del anterior y suscribe al nuevo.
  defp sync_subscription(%{flight_id: old}, %{flight_id: new} = context) when old != new do
    unsubscribe_flight(old)
    subscribe_flight(new)
    context
  end

  defp sync_subscription(_old_context, context), do: context

  defp subscribe_flight(nil), do: :ok

  defp subscribe_flight(flight_id) do
    case FlightSupervisor.lookup(flight_id) do
      {:ok, pid} -> FlightServer.subscribe(pid, self())
      :error -> :ok
    end
  end

  defp unsubscribe_flight(nil), do: :ok

  defp unsubscribe_flight(flight_id) do
    case FlightSupervisor.lookup(flight_id) do
      {:ok, pid} -> FlightServer.unsubscribe(pid, self())
      :error -> :ok
    end
  end

  # Si el pedido traía `ref`, lo espejamos en la respuesta (correlación pedido/respuesta).
  defp put_ref(response, %{"ref" => ref}), do: Map.put(response, :ref, ref)
  defp put_ref(response, _message), do: response

end
