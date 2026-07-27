defmodule Booking.Protocol do
  @moduledoc """
  Este módulo implementa el protocolo de comunicación entre el WebSocketHandler y el dominio de la aplicación.

  Recibe mensajes representados como mapas Elixir y devuelve una respuesta junto con un contexto actualizado.

  No conoce detalles de Cowboy ni de WebSocket.
  """

  alias Booking.{Persistence, User, Seed, Flight, FlightServer, Reservation}

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

  def handle(%{"type" => "open_flight", "flight_id" => flight_id}, context) do
    case context.lookup.(flight_id) do
      {:ok, pid} ->
        flight = FlightServer.get_flight(pid)

        response = %{
          type: "flight_detail",
          flight: flight_summary(flight),
          seats: seats_json(flight)
        }

        {response, %{context | flight_id: flight.id}}

      :error ->
        {error(:flight_not_found), context}
    end
  end

  # Cancela la suscripción al vuelo abierto (ver docs/protocolo.md). No valida el
  # `flight_id` recibido contra el del contexto: cerrar siempre es seguro, incluso si
  # ya estaba cerrado o si el cliente manda un id viejo.
  def handle(%{"type" => "close_flight"}, context) do
    {%{type: "closed"}, %{context | flight_id: nil}}
  end

  def handle(%{"type" => "reserve_seat"} = message, context) do
    response =
      require_user(context, fn ->
        flight_id = message["flight_id"] || context.flight_id

        with_flight(context, flight_id, fn pid ->
          case FlightServer.reserve_seat(pid, message["seat_id"], context.user_id) do
            {:ok, reservation} ->
              %{
                type: "reservation_started",
                reservation_id: reservation.id,
                flight_id: flight_id,
                seat_id: reservation.seat_id,
                expires_at: iso(reservation.expires_at)
              }

            {:error, reason} ->
              error(reason)
          end
        end)
      end)

    {response, context}
  end

  def handle(%{"type" => "pay", "reservation_id" => reservation_id}, context) do
    response =
      require_user(context, fn ->
        with_flight(context, flight_of(reservation_id), fn pid ->
          case FlightServer.pay(pid, reservation_id, context.user_id) do
            {:ok, :processing} -> %{type: "payment_started", reservation_id: reservation_id}
            {:error, reason} -> error(reason)
          end
        end)
      end)

    {response, context}
  end

  def handle(%{"type" => "cancel", "reservation_id" => reservation_id}, context) do
    response =
      require_user(context, fn ->
        with_flight(context, flight_of(reservation_id), fn pid ->
          case FlightServer.cancel(pid, reservation_id, context.user_id) do
            {:ok, reservation} ->
              %{
                type: "reservation_update",
                reservation_id: reservation.id,
                status: to_string(reservation.status)
              }

            {:error, reason} ->
              error(reason)
          end
        end)
      end)

    {response, context}
  end

  def handle(%{"type" => "my_reservations"}, context) do
    response =
      require_user(context, fn ->
        reservations =
          context.persistence
          |> Persistence.get_reservations()
          |> Enum.filter(&(&1.user_id == context.user_id))
          |> Enum.map(&reservation_json/1)

        %{type: "my_reservations", reservations: reservations}
      end)

    {response, context}
  end

  def handle(_message, context), do: {error(:invalid_message), context}

  # --- Auxiliares ---

  defp find_or_create_user(persistence, name) do
    case Enum.find(Persistence.get_users(persistence), &(&1.name == name)) do
      nil ->
        user = %User{id: "user_#{System.unique_integer([:positive])}", name: name}
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

  defp flight_summary(%Flight{} = flight) do
    flight |> flight_json(Map.new(Seed.airlines())) |> Map.delete(:seat_count)
  end

  # En la función seats_json, se obtiene la lista de asientos del vuelo y se ordena por el ID del asiento.
  # Luego, se mapea cada asiento a un mapa que contiene el ID del asiento y su estado como cadena de texto.
  defp seats_json(%Flight{} = flight) do
    flight.seats
    |> Map.values()
    |> Enum.sort_by(&String.to_integer(&1.id))
    |> Enum.map(fn seat -> %{id: seat.id, status: to_string(seat.status)} end)
  end

  defp error(reason), do: %{type: "error", reason: to_string(reason)}

  # Ejecuta `fun` solo si la conexión está registrada; si no, error :not_registered.
  defp require_user(%{user_id: nil}, _fun), do: error(:not_registered)
  defp require_user(_context, fun), do: fun.()

  # Resuelve el FlightServer del vuelo y ejecuta `fun.(pid)`; si no existe, :flight_not_found.
  defp with_flight(ctx, flight_id, fun) do
    case ctx.lookup.(flight_id) do
      {:ok, pid} -> fun.(pid)
      :error -> error(:flight_not_found)
    end
  end

  # El reservation_id tiene la forma "<flight_id>-r<n>": el prefijo es el vuelo.
  defp flight_of(reservation_id), do: reservation_id |> String.split("-r", parts: 2) |> hd()

  defp reservation_json(%Reservation{} = reservation) do
    %{
      id: reservation.id,
      flight_id: reservation.flight_id,
      seat_id: reservation.seat_id,
      status: to_string(reservation.status),
      created_at: iso(reservation.created_at),
      expires_at: iso(reservation.expires_at)
    }
  end
end
