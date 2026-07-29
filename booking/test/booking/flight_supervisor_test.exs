defmodule Booking.FlightSupervisorTest do
  # async: false porque usa el Registry y el DynamicSupervisor globales de la aplicación.
  use ExUnit.Case, async: false

  alias Booking.{Flight, FlightServer, FlightSupervisor}

  defp flight(id) do
    Flight.new(%{
      id: id,
      airline_id: "condor",
      origin: "AEP",
      destination: "BRC",
      departs_at: ~U[2026-07-20 08:30:00Z],
      price: 185_000,
      seat_count: 20
    })
  end

  # Arranca un vuelo bajo el FlightSupervisor real y lo termina al final del test
  # (para no filtrar procesos ni claves del Registry entre tests).
  defp start_flight(id) do
    {:ok, pid} = FlightSupervisor.start_flight(flight(id))

    on_exit(fn ->
      if Process.alive?(pid), do: DynamicSupervisor.terminate_child(FlightSupervisor, pid)
    end)

    pid
  end

  test "dos vuelos distintos quedan aislados y direccionables por id" do
    pid_a = start_flight("AR1001")
    pid_b = start_flight("AR2002")

    assert pid_a != pid_b
    assert {:ok, ^pid_a} = FlightSupervisor.lookup("AR1001")
    assert {:ok, ^pid_b} = FlightSupervisor.lookup("AR2002")

    {:ok, _} = FlightServer.reserve_seat(pid_a, "1", "ana")

    # El estado vive dentro de cada proceso: reservar en AR1001 no toca a AR2002.
    assert FlightServer.get_flight(pid_a).seats["1"].status == :reserved
    assert FlightServer.get_flight(pid_b).seats["1"].status == :free
  end

  test "buscar un vuelo inexistente devuelve :error" do
    assert FlightSupervisor.lookup("NOPE") == :error
  end

  test "no se puede arrancar dos veces el mismo vuelo (keys: :unique)" do
    pid = start_flight("AR3003")

    # El segundo intento con el mismo id no crea otro proceso: el Registry (keys: :unique)
    # ya tiene a ese vuelo y devuelve el pid existente. Esto sostiene "un solo FlightServer
    # por vuelo" y, con él, que los reservation_id (contador por vuelo) no colisionen.
    assert {:error, {:already_started, ^pid}} = FlightSupervisor.start_flight(flight("AR3003"))
    assert {:ok, ^pid} = FlightSupervisor.lookup("AR3003")
  end
end
