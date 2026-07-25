defmodule Booking.FlightSupervisor do
  @moduledoc """
  `DynamicSupervisor` que crea y supervisa **un `Booking.FlightServer` por vuelo**, bajo
  demanda. Los vuelos no se conocen al compilar, así que no pueden ser hijos fijos de un
  `Supervisor` clásico: este supervisor arranca cada `FlightServer` en runtime con
  `start_child` (mismo "molde", estrategia `:one_for_one`, cada vuelo independiente).

  Cada `FlightServer` se registra en `Booking.Registry` bajo la clave `{:flight, id}`
  (ver `via/1`), así se lo direcciona y se lo busca por el id del vuelo. Como el Registry
  usa `keys: :unique`, queda garantizado **un solo `FlightServer` por vuelo**.
  """

  use DynamicSupervisor

  alias Booking.{Flight, FlightServer, Reservation}

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Crea un vuelo **nuevo**: persiste su esqueleto en `Booking.Persistence` y arranca su
  `FlightServer`. Es el punto de entrada para el seed/alta de vuelos (los que después el
  restore vuelve a levantar). Devuelve lo mismo que `start_flight/2`.
  """
  @spec create_flight(Flight.t()) :: DynamicSupervisor.on_start_child()
  def create_flight(%Flight{} = flight) do
    :ok = Booking.Persistence.put_flight(flight)
    start_flight(flight)
  end

  @doc """
  Arranca el `FlightServer` de `flight` bajo este supervisor, con sus `reservations`
  persistidas a reconstruir (vacío para un vuelo nuevo). El proceso se registra en
  `Booking.Registry` por su id. Devuelve `{:ok, pid}`, o `{:error, {:already_started, pid}}`
  si ese vuelo ya está corriendo.
  """
  @spec start_flight(Flight.t(), [Reservation.t()]) :: DynamicSupervisor.on_start_child()
  def start_flight(%Flight{} = flight, reservations \\ []) do
    # Inyecta el Persistence singleton: los FlightServer de producción persisten
    # (write-through); los que se arrancan sueltos en tests no (persistence: nil por defecto).
    DynamicSupervisor.start_child(
      __MODULE__,
      {FlightServer,
       flight: flight,
       name: via(flight.id),
       persistence: Booking.Persistence,
       reservations: reservations}
    )
  end

  @doc """
  Busca el `FlightServer` de un vuelo por id: `{:ok, pid}` si está corriendo, `:error` si no.
  """
  @spec lookup(String.t()) :: {:ok, pid()} | :error
  def lookup(flight_id) do
    case Registry.lookup(Booking.Registry, {:flight, flight_id}) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end

  # Nombre direccionable de un vuelo: un via-tuple que registra/resuelve el proceso en
  # `Booking.Registry` bajo la clave `{:flight, id}`.
  defp via(flight_id), do: {:via, Registry, {Booking.Registry, {:flight, flight_id}}}
end
