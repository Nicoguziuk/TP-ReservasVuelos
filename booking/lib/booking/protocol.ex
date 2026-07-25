defmodule Booking.Protocol do
  @moduledoc """
  Este módulo implementa el protocolo de comunicación entre el WebSocketHandler y el dominio de la aplicación.

  Recibe mensajes representados como mapas Elixir y devuelve una respuesta junto con un contexto actualizado.

  No conoce detalles de Cowboy ni de WebSocket.
  """

  alias Booking.{Persistence, User}

  def handle(%{"type" => "register", "name" => name}, context) do
    user = find_or_create_user(name, context.persistence)

    response = %{
      type: "registered",
      user_id: user.id,
      name: user.name
    }

    new_context = Map.put(context, :user_id, user.id)

    {response, new_context}
  end

  def handle(%{"type" => "list_flights"}, context) do
    {%{type: "list_flights_response"}, context}
  end

  def handle(%{"type" => "open_flight"}, context) do
    {%{type: "open_flight_response"}, context}
  end

  def handle(%{"type" => "close_flight"}, context) do
    {%{type: "close_flight_response"}, context}
  end

  def handle(%{"type" => "reserve_seat"}, context) do
    {%{type: "reserve_seat_response"}, context}
  end

  def handle(%{"type" => "pay"}, context) do
    {%{type: "pay_received"}, context}
  end

  def handle(%{"type" => "cancel"}, context) do
    {%{type: "cancel_received"}, context}
  end

  def handle(%{"type" => "my_reservations"}, context) do
    {%{type: "my_reservations_response"}, context}
  end

  def handle(_message, context) do
    {%{type: "error", reason: "invalid_message"}, context}
  end

  defp find_or_create_user(name, persistence) do
    users = Persistence.get_users(persistence)

    case Enum.find(users, fn user -> user.name == name end) do
      nil ->
        user = User.new(name)
        :ok = Persistence.put_user(user, persistence)
        user

      user ->
        user
    end
  end
end
