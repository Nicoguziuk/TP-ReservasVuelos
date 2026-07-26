defmodule Booking.Boot do
  @moduledoc """
  Arranque del backend: lo llama `Booking.Application.start/2` después de levantar el árbol.
  Decide entre **seed** y **restore** según el estado de DETS:

    * si la tabla `flights` está **vacía** (primer arranque) → siembra el catálogo inicial
      (`Booking.Seed.flights/0`) en Persistence;
    * en cualquier caso → `restore`: levanta un `FlightServer` por vuelo persistido con sus
      reservas (un solo camino para vuelos seedeados y restaurados).

  Así nunca duplica: con datos, el seed no hace nada; con DETS vacío, siembra y después
  `restore` arranca lo recién sembrado (con reservas vacías).

  `restore` lee DETS **una sola vez** (`get_flights` + `get_reservations`) y agrupa las
  reservas por vuelo en memoria, en vez de que cada `FlightServer` escanee toda la tabla.
  """

  alias Booking.{FlightSupervisor, Persistence, Seed}

  @doc "Punto de entrada del arranque: siembra si hace falta y restaura los vuelos."
  @spec run() :: :ok
  def run do
    if Application.get_env(:booking, :seed_on_boot, true), do: seed_if_empty()
    restore()
  end

  @doc """
  Siembra el catálogo inicial **solo si** la tabla de vuelos está vacía (idempotente: con
  datos no agrega nada). `persistence` permite apuntar a una instancia aislada en tests.
  """
  @spec seed_if_empty(GenServer.server()) :: :ok
  def seed_if_empty(persistence \\ Booking.Persistence) do
    if Persistence.get_flights(persistence) == [] do
      Enum.each(Seed.flights(), &Persistence.put_flight(&1, persistence))
    end

    :ok
  end

  # Levanta un FlightServer por vuelo persistido, con sus reservas reconstruidas.
  defp restore do
    reservations_by_flight = Enum.group_by(Persistence.get_reservations(), & &1.flight_id)

    Enum.each(Persistence.get_flights(), fn flight ->
      FlightSupervisor.start_flight(flight, Map.get(reservations_by_flight, flight.id, []))
    end)

    :ok
  end
end
