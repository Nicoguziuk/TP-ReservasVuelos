defmodule Booking.FlightServerTest do
  use ExUnit.Case, async: true

  alias Booking.{Flight, FlightServer, Persistence, Reservation}

  # Arranca un FlightServer supervisado por el test (se limpia solo al terminar).
  # `opts` puede incluir `:seat_count`, `:ttl_ms`, `:persistence` y `:reservations`.
  defp start_server(opts \\ []) do
    flight = build_flight("AR1001", Keyword.get(opts, :seat_count, 20))
    extra = Keyword.take(opts, [:ttl_ms, :persistence, :reservations])
    start_supervised!({FlightServer, [flight: flight] ++ extra})
  end

  defp build_flight(id, seat_count \\ 20) do
    Flight.new(%{
      id: id,
      airline_id: "condor",
      origin: "AEP",
      destination: "BRC",
      departs_at: ~U[2026-07-20 08:30:00Z],
      price: 185_000,
      seat_count: seat_count
    })
  end

  # Arranca un Persistence aislado (nombre único + carpeta temporal) y devuelve su nombre.
  defp start_persistence(tmp_dir) do
    name = :"persistence_#{System.unique_integer([:positive])}"
    start_supervised!({Persistence, name: name, dir: tmp_dir})
    name
  end

  test "reservar a través del server marca el asiento y devuelve la reserva pendiente" do
    server = start_server()

    assert {:ok, reservation} = FlightServer.reserve_seat(server, "1", "ana")
    assert reservation.status == :pending
    assert reservation.seat_id == "1"
    assert reservation.user_id == "ana"
    assert reservation.id == "AR1001-r1"
    assert FlightServer.get_flight(server).seats["1"].status == :reserved
  end

  test "el server genera ids de reserva incrementales" do
    server = start_server()

    {:ok, r1} = FlightServer.reserve_seat(server, "1", "ana")
    {:ok, r2} = FlightServer.reserve_seat(server, "2", "ana")

    assert r1.id == "AR1001-r1"
    assert r2.id == "AR1001-r2"
  end

  test "confirmar deja el asiento ocupado; cancelar lo libera (a través del server)" do
    server = start_server()

    {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")
    assert {:ok, confirmed} = FlightServer.confirm(server, res.id)
    assert confirmed.status == :confirmed
    assert FlightServer.get_flight(server).seats["1"].status == :confirmed

    {:ok, res2} = FlightServer.reserve_seat(server, "2", "ana")
    assert {:ok, cancelled} = FlightServer.cancel(server, res2.id, "ana")
    assert cancelled.status == :cancelled
    assert FlightServer.get_flight(server).seats["2"].status == :free
  end

  test "reservar un asiento ya ocupado falla" do
    server = start_server()
    {:ok, _} = FlightServer.reserve_seat(server, "1", "ana")

    assert {:error, :seat_taken} = FlightServer.reserve_seat(server, "1", "beto")
  end

  test "100 usuarios piden el mismo asiento a la vez: gana exactamente uno" do
    server = start_server()

    # Este test demuestra la SERIALIZACIÓN del GenServer: lanzamos 100 pedidos del mismo
    # asiento "en paralelo", pero el FlightServer atiende su mailbox de a un mensaje por
    # vez, así que solo el primero ve el asiento libre. Aunque las 100 llamadas "lleguen
    # juntas", gana exactamente 1 y los otros 99 reciben :seat_taken. Sin locks.
    results =
      1..100
      |> Task.async_stream(
        fn i -> FlightServer.reserve_seat(server, "1", "user_#{i}") end,
        max_concurrency: 100,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    winners = Enum.filter(results, &match?({:ok, _}, &1))
    losers = Enum.filter(results, &match?({:error, :seat_taken}, &1))

    assert length(winners) == 1
    assert length(losers) == 99
    assert FlightServer.get_flight(server).seats["1"].status == :reserved
  end

  describe "expiración y conflictos" do
    test "la expiración real (TTL corto) libera el asiento" do
      server = start_server(ttl_ms: 30)
      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")
      assert FlightServer.get_flight(server).seats["1"].status == :reserved

      Process.sleep(80)

      flight = FlightServer.get_flight(server)
      assert flight.reservations[res.id].status == :expired
      assert flight.seats["1"].status == :free
    end

    test "confirmar una reserva ya expirada falla y no toca el asiento" do
      server = start_server(ttl_ms: 30)
      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")
      Process.sleep(80)

      assert {:error, :not_pending} = FlightServer.confirm(server, res.id)
      assert FlightServer.get_flight(server).seats["1"].status == :free
    end

    test "confirmar-vs-expirar: si confirmo, un {:expire} tardío es no-op" do
      server = start_server()
      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")
      {:ok, _} = FlightServer.confirm(server, res.id)

      # Simulo que el timer dispara TARDE (después de confirmar): handle_info re-valida
      # con Flight.expire y, como la reserva ya está :confirmed, no hace nada.
      send(server, {:expire, res.id})

      # get_flight se procesa después del {:expire} (misma mailbox) → estado estabilizado.
      flight = FlightServer.get_flight(server)
      assert flight.reservations[res.id].status == :confirmed
      assert flight.seats["1"].status == :confirmed
    end

    test "cancelar-vs-confirmar: si cancelo, confirmar después es no-op" do
      server = start_server()
      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")
      {:ok, _} = FlightServer.cancel(server, res.id, "ana")

      assert {:error, :not_pending} = FlightServer.confirm(server, res.id)
      assert FlightServer.get_flight(server).seats["1"].status == :free
    end
  end

  describe "write-through (persistencia)" do
    @tag :tmp_dir
    test "cada cambio de reserva se persiste con su estado actualizado", %{tmp_dir: tmp_dir} do
      pname = :"persistence_#{System.unique_integer([:positive])}"
      start_supervised!({Persistence, name: pname, dir: tmp_dir})
      server = start_server(persistence: pname)

      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")
      assert [stored] = Persistence.get_reservations(pname)
      assert stored.id == res.id
      assert stored.status == :pending

      {:ok, _} = FlightServer.confirm(server, res.id)
      assert [stored] = Persistence.get_reservations(pname)
      assert stored.status == :confirmed
    end

    @tag :tmp_dir
    test "la expiración también se persiste (queda :expired en Persistence)", %{tmp_dir: tmp_dir} do
      pname = :"persistence_#{System.unique_integer([:positive])}"
      start_supervised!({Persistence, name: pname, dir: tmp_dir})
      server = start_server(ttl_ms: 30, persistence: pname)

      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")
      Process.sleep(80)

      # La expiración real disparó el timer -> handle_info -> persist(:expired).
      assert [stored] = Persistence.get_reservations(pname)
      assert stored.id == res.id
      assert stored.status == :expired
    end
  end

  describe "restore (reconstrucción desde DETS)" do
    @tag :tmp_dir
    test "estrella: crear + confirmar → apagar → levantar → sigue confirmado", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      flight = build_flight("AR1001")
      :ok = Persistence.put_flight(flight, p)

      # Crear + confirmar en el server 1 (write-through persiste todo).
      s1 = start_supervised!({FlightServer, flight: flight, persistence: p}, id: :s1)
      {:ok, res} = FlightServer.reserve_seat(s1, "1", "ana")
      {:ok, _} = FlightServer.confirm(s1, res.id)
      :ok = stop_supervised(:s1)

      # "Levantar desde disco": releer el vuelo y sus reservas, y reconstruir.
      [flight2] = Persistence.get_flights(p)

      s2 =
        start_supervised!(
          {FlightServer,
           flight: flight2, reservations: Persistence.get_reservations(p), persistence: p},
          id: :s2
        )

      assert FlightServer.get_flight(s2).seats["1"].status == :confirmed
      assert FlightServer.get_flight(s2).reservations[res.id].status == :confirmed
    end

    @tag :tmp_dir
    test "una :pending ya vencida vuelve :expired y libera el asiento", %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      flight = build_flight("AR1001")
      :ok = Persistence.put_flight(flight, p)

      # Reserva :pending con expires_at en el pasado (created hace 60 s, ttl 1 s).
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      res = Reservation.new("AR1001-r1", "AR1001", "1", "ana", past, 1000)
      :ok = Persistence.put_reservation(res, p)

      s = start_supervised!({FlightServer, flight: flight, reservations: [res], persistence: p})

      flight_state = FlightServer.get_flight(s)
      assert flight_state.seats["1"].status == :free
      assert flight_state.reservations["AR1001-r1"].status == :expired
      # La corrección quedó persistida.
      assert [stored] = Persistence.get_reservations(p)
      assert stored.status == :expired
    end

    @tag :tmp_dir
    test "una :pending vigente vuelve :reserved y el timer re-armado la expira", %{
      tmp_dir: tmp_dir
    } do
      p = start_persistence(tmp_dir)
      flight = build_flight("AR1001")
      :ok = Persistence.put_flight(flight, p)

      # Reserva :pending con ~200 ms restantes al momento de restaurar.
      res = Reservation.new("AR1001-r1", "AR1001", "1", "ana", DateTime.utc_now(), 200)
      :ok = Persistence.put_reservation(res, p)

      s = start_supervised!({FlightServer, flight: flight, reservations: [res], persistence: p})

      # Recién restaurada: asiento :reserved (timer re-armado por el tiempo restante).
      assert FlightServer.get_flight(s).seats["1"].status == :reserved

      # Al vencer el tiempo restante, el timer re-armado la expira sola.
      Process.sleep(260)
      flight_after = FlightServer.get_flight(s)
      assert flight_after.seats["1"].status == :free
      assert flight_after.reservations["AR1001-r1"].status == :expired
    end

    @tag :tmp_dir
    test "aplica solo la reserva activa: expirar y re-reservar el mismo asiento → :confirmed",
         %{tmp_dir: tmp_dir} do
      p = start_persistence(tmp_dir)
      flight = build_flight("AR1001")
      :ok = Persistence.put_flight(flight, p)

      s1 = start_supervised!({FlightServer, flight: flight, persistence: p, ttl_ms: 30}, id: :s1)
      {:ok, r1} = FlightServer.reserve_seat(s1, "1", "ana")
      Process.sleep(80)
      # r1 expiró (timer) → :expired, asiento libre, persistido.
      {:ok, r2} = FlightServer.reserve_seat(s1, "1", "beto")
      {:ok, _} = FlightServer.confirm(s1, r2.id)
      :ok = stop_supervised(:s1)

      # Dos reservas para el asiento "1" en el historial: r1 :expired, r2 :confirmed.
      reservations = Persistence.get_reservations(p)
      assert length(reservations) == 2

      [flight2] = Persistence.get_flights(p)

      s2 =
        start_supervised!(
          {FlightServer, flight: flight2, reservations: reservations, persistence: p},
          id: :s2
        )

      # El asiento queda :confirmed (la reserva activa), sin importar el orden de iteración.
      assert FlightServer.get_flight(s2).seats["1"].status == :confirmed
      # Ambas reservas en el historial.
      assert FlightServer.get_flight(s2).reservations[r1.id].status == :expired
      assert FlightServer.get_flight(s2).reservations[r2.id].status == :confirmed
    end
  end

  describe "pago simulado" do
    test "pago OK confirma la reserva" do
      server = start_server()
      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")

      assert {:ok, :processing} = FlightServer.pay(server, res.id, "ana", force: :ok, delay: 10)
      Process.sleep(40)

      flight = FlightServer.get_flight(server)
      assert flight.reservations[res.id].status == :confirmed
      assert flight.seats["1"].status == :confirmed
    end

    test "un pago que llega después de expirar NO confirma (queda :expired)" do
      server = start_server(ttl_ms: 30)
      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")

      # delay del pago (100 ms) > ttl (30 ms): la expiración entra primero.
      assert {:ok, :processing} = FlightServer.pay(server, res.id, "ana", force: :ok, delay: 100)
      Process.sleep(160)

      flight = FlightServer.get_flight(server)
      assert flight.reservations[res.id].status == :expired
      assert flight.seats["1"].status == :free
    end

    test "pago rechazado: la reserva sigue :pending" do
      server = start_server()
      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")

      assert {:ok, :processing} =
               FlightServer.pay(server, res.id, "ana", force: :error, delay: 10)

      Process.sleep(40)

      flight = FlightServer.get_flight(server)
      assert flight.reservations[res.id].status == :pending
      assert flight.seats["1"].status == :reserved
    end

    test "doble-pay: el segundo pago concurrente es rechazado" do
      server = start_server()
      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")

      assert {:ok, :processing} = FlightServer.pay(server, res.id, "ana", force: :ok, delay: 50)

      assert {:error, :payment_in_progress} =
               FlightServer.pay(server, res.id, "ana", force: :ok, delay: 50)
    end

    test "pagar/cancelar una reserva de otro usuario falla con :not_owner" do
      server = start_server()
      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")

      assert {:error, :not_owner} =
               FlightServer.pay(server, res.id, "beto", force: :ok, delay: 10)

      assert {:error, :not_owner} = FlightServer.cancel(server, res.id, "beto")
      # La dueña sí puede cancelar.
      assert {:ok, _} = FlightServer.cancel(server, res.id, "ana")
    end
  end

  describe "broadcast / suscripción" do
    test "un suscriptor recibe seat_update cuando otro reserva" do
      server = start_server()
      FlightServer.subscribe(server, self())

      {:ok, _} = FlightServer.reserve_seat(server, "1", "ana")

      assert_receive {:push, %{type: "seat_update", seat_id: "1", status: "reserved"}}
    end

    test "un suscriptor que muere se limpia sin crashear el server" do
      server = start_server()
      dead = spawn(fn -> :ok end)
      ref = Process.monitor(dead)
      assert_receive {:DOWN, ^ref, :process, ^dead, _}

      FlightServer.subscribe(server, dead)
      # El server sigue operando normalmente (no crashea por el pid muerto).
      assert {:ok, _} = FlightServer.reserve_seat(server, "1", "ana")
      assert Process.alive?(server)
    end

    test "varios suscriptores reciben el seat_update" do
      server = start_server()
      parent = self()
      other = spawn_link(fn -> relay(parent) end)

      FlightServer.subscribe(server, self())
      FlightServer.subscribe(server, other)
      {:ok, _} = FlightServer.reserve_seat(server, "1", "ana")

      assert_receive {:push, %{type: "seat_update", seat_id: "1"}}
      assert_receive {:relayed, {:push, %{type: "seat_update", seat_id: "1"}}}
    end

    test "al confirmar el pago se pushea reservation_update + seat_update" do
      server = start_server()
      FlightServer.subscribe(server, self())
      {:ok, res} = FlightServer.reserve_seat(server, "1", "ana")
      assert_receive {:push, %{type: "seat_update", status: "reserved"}}

      {:ok, :processing} = FlightServer.pay(server, res.id, "ana", force: :ok, delay: 10)

      assert_receive {:push,
                      %{type: "reservation_update", reservation_id: rid, status: "confirmed"}},
                     300

      assert rid == res.id
      assert_receive {:push, %{type: "seat_update", status: "confirmed"}}
    end
  end

  # Reenvía al `parent` (con tag) lo que reciba; sirve para tener un 2º suscriptor en tests.
  defp relay(parent) do
    receive do
      message ->
        send(parent, {:relayed, message})
        relay(parent)
    end
  end
end
