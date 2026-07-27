defmodule Booking.ProtocolTest do
  use ExUnit.Case, async: true

  alias Booking.{Flight, FlightServer, Persistence, Protocol}

  defp base_ctx(persistence) do
    %{user_id: nil, flight_id: nil, persistence: persistence, lookup: fn _ -> :error end}
  end

  defp start_persistence(tmp_dir) do
    name = :"persistence_#{System.unique_integer([:positive])}"
    start_supervised!({Persistence, name: name, dir: tmp_dir})
    name
  end

  defp build_flight(id) do
    Flight.new(%{
      id: id,
      airline_id: "CDS",
      origin: "AEP",
      destination: "BRC",
      departs_at: ~U[2026-07-20 08:00:00Z],
      price: 185_000,
      seat_count: 20
    })
  end

  defp put_test_flight(persistence, id, destination, departs_at, price) do
    flight =
      Flight.new(%{
        id: id,
        airline_id: "CDS",
        origin: "AEP",
        destination: destination,
        departs_at: departs_at,
        price: price,
        seat_count: 20
      })

    :ok = Persistence.put_flight(flight, persistence)
  end

  # Arranca un FlightServer (con la persistence aislada) y devuelve {pid, lookup}.
  defp start_flight(persistence, id) do
    pid = start_supervised!({FlightServer, flight: build_flight(id), persistence: persistence})

    lookup = fn
      ^id -> {:ok, pid}
      _ -> :error
    end

    {pid, lookup}
  end

  describe "register" do
    @tag :tmp_dir
    test "crea un usuario y guarda el user_id en el contexto", %{tmp_dir: tmp_dir} do
      ctx = base_ctx(start_persistence(tmp_dir))

      assert {%{type: "registered", user_id: user_id, name: "Ana"}, new_ctx} =
               Protocol.handle(%{"type" => "register", "name" => "Ana"}, ctx)

      assert is_binary(user_id)
      assert new_ctx.user_id == user_id
    end

    @tag :tmp_dir
    test "registrarse con el mismo nombre reusa el user_id", %{tmp_dir: tmp_dir} do
      ctx = base_ctx(start_persistence(tmp_dir))

      {%{user_id: id1}, _} = Protocol.handle(%{"type" => "register", "name" => "Ana"}, ctx)
      {%{user_id: id2}, _} = Protocol.handle(%{"type" => "register", "name" => "Ana"}, ctx)

      assert id1 == id2
    end
  end

  describe "list_flights" do
    @tag :tmp_dir
    test "devuelve los vuelos persistidos con la aerolínea mapeada", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      :ok = Persistence.put_flight(build_flight("CDS101"), p)

      assert {%{type: "flights", flights: [flight]}, _ctx} =
               Protocol.handle(%{"type" => "list_flights"}, base_ctx(p))

      assert flight.id == "CDS101"
      assert flight.airline == "Cóndor del Sur"
      assert flight.seat_count == 20
    end

    @tag :tmp_dir
    test "filtra por destino", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      put_test_flight(p, "A", "BRC", ~U[2026-07-20 08:00:00Z], 100_000)
      put_test_flight(p, "B", "MDZ", ~U[2026-07-20 08:00:00Z], 100_000)

      assert {%{flights: flights}, _} =
               Protocol.handle(%{"type" => "list_flights", "destination" => "BRC"}, base_ctx(p))

      assert Enum.map(flights, & &1.id) == ["A"]
    end

    @tag :tmp_dir
    test "filtra por fecha", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      put_test_flight(p, "A", "BRC", ~U[2026-07-20 08:00:00Z], 100_000)
      put_test_flight(p, "B", "BRC", ~U[2026-07-21 08:00:00Z], 100_000)

      assert {%{flights: flights}, _} =
               Protocol.handle(%{"type" => "list_flights", "date" => "2026-07-21"}, base_ctx(p))

      assert Enum.map(flights, & &1.id) == ["B"]
    end

    @tag :tmp_dir
    test "ordena por precio asc y desc", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      put_test_flight(p, "cara", "BRC", ~U[2026-07-20 08:00:00Z], 300_000)
      put_test_flight(p, "barata", "BRC", ~U[2026-07-20 08:00:00Z], 100_000)

      {%{flights: asc}, _} =
        Protocol.handle(%{"type" => "list_flights", "sort" => "price_asc"}, base_ctx(p))

      assert Enum.map(asc, & &1.id) == ["barata", "cara"]

      {%{flights: desc}, _} =
        Protocol.handle(%{"type" => "list_flights", "sort" => "price_desc"}, base_ctx(p))

      assert Enum.map(desc, & &1.id) == ["cara", "barata"]
    end
  end

  describe "open_flight" do
    @tag :tmp_dir
    test "devuelve detalle + asientos y guarda flight_id", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      {_pid, lookup} = start_flight(p, "CDS101")
      ctx = %{base_ctx(p) | lookup: lookup}

      assert {%{type: "flight_detail", flight: flight, seats: seats}, new_ctx} =
               Protocol.handle(%{"type" => "open_flight", "flight_id" => "CDS101"}, ctx)

      assert flight.id == "CDS101"
      assert length(seats) == 20
      assert Enum.all?(seats, &(&1.status == "free"))
      assert new_ctx.flight_id == "CDS101"
    end

    @tag :tmp_dir
    test "vuelo inexistente devuelve flight_not_found", %{tmp_dir: tmp_dir} do
      assert {%{type: "error", reason: "flight_not_found"}, _} =
               Protocol.handle(
                 %{"type" => "open_flight", "flight_id" => "NOPE"},
                 base_ctx(start_persistence(tmp_dir))
               )
    end
  end

  describe "close_flight" do
    @tag :tmp_dir
    test "limpia el flight_id del contexto (desuscribe el vuelo abierto)", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      {_pid, lookup} = start_flight(p, "CDS101")
      ctx = %{base_ctx(p) | lookup: lookup, flight_id: "CDS101"}

      assert {%{type: "closed"}, new_ctx} =
               Protocol.handle(%{"type" => "close_flight", "flight_id" => "CDS101"}, ctx)

      assert new_ctx.flight_id == nil
    end

    @tag :tmp_dir
    test "es un no-op seguro si no había ningún vuelo abierto", %{tmp_dir: tmp_dir} do
      ctx = base_ctx(start_persistence(tmp_dir))

      assert {%{type: "closed"}, new_ctx} =
               Protocol.handle(%{"type" => "close_flight", "flight_id" => "NOPE"}, ctx)

      assert new_ctx.flight_id == nil
    end
  end

  describe "reserve_seat" do
    @tag :tmp_dir
    test "inicia la reserva", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      {_pid, lookup} = start_flight(p, "CDS101")
      ctx = %{base_ctx(p) | lookup: lookup, user_id: "user_ana"}

      assert {%{
                type: "reservation_started",
                reservation_id: rid,
                seat_id: "1",
                flight_id: "CDS101"
              }, _} =
               Protocol.handle(
                 %{"type" => "reserve_seat", "flight_id" => "CDS101", "seat_id" => "1"},
                 ctx
               )

      assert rid == "CDS101-r1"
    end

    @tag :tmp_dir
    test "sin registrarse devuelve not_registered", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      {_pid, lookup} = start_flight(p, "CDS101")
      ctx = %{base_ctx(p) | lookup: lookup}

      assert {%{type: "error", reason: "not_registered"}, _} =
               Protocol.handle(
                 %{"type" => "reserve_seat", "flight_id" => "CDS101", "seat_id" => "1"},
                 ctx
               )
    end

    @tag :tmp_dir
    test "asiento ya tomado devuelve seat_taken", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      {pid, lookup} = start_flight(p, "CDS101")
      {:ok, _} = FlightServer.reserve_seat(pid, "1", "otro")
      ctx = %{base_ctx(p) | lookup: lookup, user_id: "user_ana"}

      assert {%{type: "error", reason: "seat_taken"}, _} =
               Protocol.handle(
                 %{"type" => "reserve_seat", "flight_id" => "CDS101", "seat_id" => "1"},
                 ctx
               )
    end
  end

  describe "pay" do
    @tag :tmp_dir
    test "devuelve el ack payment_started", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      {pid, lookup} = start_flight(p, "CDS101")
      {:ok, res} = FlightServer.reserve_seat(pid, "1", "user_ana")
      ctx = %{base_ctx(p) | lookup: lookup, user_id: "user_ana"}

      assert {%{type: "payment_started", reservation_id: rid}, _} =
               Protocol.handle(%{"type" => "pay", "reservation_id" => res.id}, ctx)

      assert rid == res.id
    end

    @tag :tmp_dir
    test "reserva ajena devuelve not_owner", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      {pid, lookup} = start_flight(p, "CDS101")
      {:ok, res} = FlightServer.reserve_seat(pid, "1", "user_ana")
      ctx = %{base_ctx(p) | lookup: lookup, user_id: "user_beto"}

      assert {%{type: "error", reason: "not_owner"}, _} =
               Protocol.handle(%{"type" => "pay", "reservation_id" => res.id}, ctx)
    end
  end

  describe "cancel" do
    @tag :tmp_dir
    test "cancela y devuelve reservation_update cancelled", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      {pid, lookup} = start_flight(p, "CDS101")
      {:ok, res} = FlightServer.reserve_seat(pid, "1", "user_ana")
      ctx = %{base_ctx(p) | lookup: lookup, user_id: "user_ana"}

      assert {%{type: "reservation_update", reservation_id: rid, status: "cancelled"}, _} =
               Protocol.handle(%{"type" => "cancel", "reservation_id" => res.id}, ctx)

      assert rid == res.id
    end
  end

  describe "my_reservations" do
    @tag :tmp_dir
    test "devuelve solo las reservas del usuario", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      {pid, lookup} = start_flight(p, "CDS101")
      {:ok, _} = FlightServer.reserve_seat(pid, "1", "user_ana")
      {:ok, _} = FlightServer.reserve_seat(pid, "2", "user_beto")
      ctx = %{base_ctx(p) | lookup: lookup, user_id: "user_ana"}

      assert {%{type: "my_reservations", reservations: reservations}, _} =
               Protocol.handle(%{"type" => "my_reservations"}, ctx)

      assert length(reservations) == 1
      assert hd(reservations).seat_id == "1"
    end

    @tag :tmp_dir
    test "sin registrarse devuelve not_registered", %{tmp_dir: tmp_dir} do
      assert {%{type: "error", reason: "not_registered"}, _} =
               Protocol.handle(
                 %{"type" => "my_reservations"},
                 base_ctx(start_persistence(tmp_dir))
               )
    end
  end

  test "un mensaje desconocido devuelve invalid_message" do
    assert {%{type: "error", reason: "invalid_message"}, _} =
             Protocol.handle(%{"type" => "nope"}, base_ctx(nil))
  end
end
