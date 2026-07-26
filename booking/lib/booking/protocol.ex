defmodule Booking.Protocol do
  @moduledoc """
  Este módulo implementa el protocolo de comunicación entre el WebSocketHandler y el dominio de la aplicación.

  Recibe mensajes representados como mapas Elixir y devuelve una respuesta junto con un contexto actualizado.

  No conoce detalles de Cowboy ni de WebSocket.
  """

  alias Booking.{Persistence, User, Seed, Flight}

  def handle(%{"type" => "register", "name" => name}, context) do
    user = find_or_create_user(context.persistence, name)

    {%{
      type: "registered",
      user_id: user.id,
      name: user.name
    }, %{context | user_id: user.id}}
  end

  def handle(%{"type" => "list_flights"} = message, context) do
    airlines = Map.new(Seed.airlines())

    flights = context.persistence
    |> Persistence.get_flights()
    |> filter_by_date(message["date"])
    |> filter_by_destination(message["destination"])
    |> sort_flights(message["sort"])
    |> Enum.map(&flight_json(&1, airlines))

    {%{type: "flights", flights: flights}, context}
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

  # En el filtro por fecha se compara la fecha de salida del vuelo con la fecha proporcionada en el mensaje.
  # Si la fecha es nil o una cadena vacía, se devuelve la lista completa de vuelos sin filtrar.
  defp filter_by_date(flights, date) when date in [nil, ""], do: flights

  defp filter_by_date(flights, date) do
    Enum.filter(flights, fn flight ->
      flight.departs_at
      |> DateTime.to_date()
      |> Date.to_iso8601() == date
    end)
  end

  # En el filtro por destino se compara el destino del vuelo con el destino proporcionado en el mensaje.
  # Si el destino es nil o una cadena vacía, se devuelve la lista completa de vuelos sin filtrar.
  defp filter_by_destination(flights, destination) when destination in [nil, ""], do: flights
  defp filter_by_destination(flights, dest), do: Enum.filter(flights, &(&1.destination == dest))

  # En la función de ordenamiento, se ordenan los vuelos según el criterio proporcionado en el mensaje.
  # Si el criterio es "price_asc", se ordena por precio de menor a mayor. Si es "price_desc", se ordena por precio de mayor a menor.
  # Si no se proporciona un criterio válido, se devuelve la lista de vuelos sin ordenar.
  defp sort_flights(flights, "price_asc"), do: Enum.sort_by(flights, & &1.price, :asc)
  defp sort_flights(flights, "price_desc"), do: Enum.sort_by(flights, & &1.price, :desc)
  defp sort_flights(flights, _sort), do: flights

  defp flight_json(%Flight{} = flight, airlines) do
    %{
      id: flight.id,
      airline: Map.get(airlines, flight.airline_id, flight.airline_id),
      origin: flight.origin,
      destination: flight.destination,
      departs_at: iso(flight.departs_at),
      price: flight.price,
      seat_count: map_size(flight.seats)
    }
  end

  defp iso(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
