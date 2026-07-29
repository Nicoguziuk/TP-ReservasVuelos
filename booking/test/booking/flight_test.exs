defmodule Booking.FlightTest do
  use ExUnit.Case, async: true

  alias Booking.{Flight, Reservation}

  # Vuelo de prueba con 20 asientos ("1".."20").
  defp new_flight do
    Flight.new(%{
      id: "AR1001",
      airline_id: "condor",
      origin: "AEP",
      destination: "BRC",
      departs_at: ~U[2026-07-20 08:30:00Z],
      price: 185_000,
      seat_count: 20
    })
  end

  defp now, do: ~U[2026-07-20 08:00:00Z]

  describe "new/1" do
    test "crea todos los asientos libres y sin reservas" do
      flight = new_flight()
      assert map_size(flight.seats) == 20
      assert Enum.all?(flight.seats, fn {_id, seat} -> seat.status == :free end)
      assert flight.reservations == %{}
    end
  end

  describe "reserve_seat/5" do
    test "reserva un asiento libre: queda :reserved y la reserva :pending" do
      flight = new_flight()

      assert {:ok, {flight, reservation}} =
               Flight.reserve_seat(flight, "1", "user_a", "res_1", now())

      assert %Reservation{status: :pending, seat_id: "1", user_id: "user_a"} = reservation
      assert flight.seats["1"].status == :reserved
      assert flight.seats["1"].held_by == "res_1"
      assert flight.reservations["res_1"].status == :pending
    end

    test "expires_at = created_at + 1 minuto" do
      {:ok, {_flight, reservation}} =
        Flight.reserve_seat(new_flight(), "1", "user_a", "res_1", now())

      assert reservation.created_at == now()
      assert DateTime.diff(reservation.expires_at, reservation.created_at, :second) == 60
    end

    test "reservar un asiento ya ocupado falla: solo uno lo consigue" do
      flight = new_flight()
      {:ok, {flight, _}} = Flight.reserve_seat(flight, "1", "user_a", "res_1", now())

      assert {:error, :seat_taken} =
               Flight.reserve_seat(flight, "1", "user_b", "res_2", now())

      # El asiento sigue en manos del primero.
      assert flight.seats["1"].held_by == "res_1"
    end

    test "reservar un asiento inexistente falla" do
      assert {:error, :seat_not_found} =
               Flight.reserve_seat(new_flight(), "999", "user_a", "res_1", now())
    end
  end

  describe "confirm/2" do
    test "confirma una reserva pendiente: reserva :confirmed y asiento ocupado" do
      flight = new_flight()
      {:ok, {flight, _}} = Flight.reserve_seat(flight, "1", "user_a", "res_1", now())

      assert {:ok, flight} = Flight.confirm(flight, "res_1")
      assert flight.reservations["res_1"].status == :confirmed
      assert flight.seats["1"].status == :confirmed
    end

    test "no se puede confirmar una reserva expirada (pago tardío no confirma)" do
      flight = new_flight()
      {:ok, {flight, _}} = Flight.reserve_seat(flight, "1", "user_a", "res_1", now())
      {:ok, flight} = Flight.expire(flight, "res_1")

      assert {:error, :not_pending} = Flight.confirm(flight, "res_1")
      # El estado final no cambió.
      assert flight.reservations["res_1"].status == :expired
      assert flight.seats["1"].status == :free
    end

    test "confirmar una reserva inexistente falla" do
      assert {:error, :reservation_not_found} = Flight.confirm(new_flight(), "nope")
    end
  end

  describe "cancel/2" do
    test "cancela una reserva pendiente: reserva :cancelled y asiento liberado" do
      flight = new_flight()
      {:ok, {flight, _}} = Flight.reserve_seat(flight, "1", "user_a", "res_1", now())

      assert {:ok, flight} = Flight.cancel(flight, "res_1")
      assert flight.reservations["res_1"].status == :cancelled
      assert flight.seats["1"].status == :free
      assert flight.seats["1"].held_by == nil
    end

    test "no se puede cancelar una reserva ya confirmada" do
      flight = new_flight()
      {:ok, {flight, _}} = Flight.reserve_seat(flight, "1", "user_a", "res_1", now())
      {:ok, flight} = Flight.confirm(flight, "res_1")

      assert {:error, :not_pending} = Flight.cancel(flight, "res_1")
      assert flight.reservations["res_1"].status == :confirmed
      assert flight.seats["1"].status == :confirmed
    end
  end

  describe "expire/2" do
    test "expira una reserva pendiente: reserva :expired y asiento liberado" do
      flight = new_flight()
      {:ok, {flight, _}} = Flight.reserve_seat(flight, "1", "user_a", "res_1", now())

      assert {:ok, flight} = Flight.expire(flight, "res_1")
      assert flight.reservations["res_1"].status == :expired
      assert flight.seats["1"].status == :free
    end
  end

  describe "invariantes: liberar vs. ocupar" do
    test "confirmar deja ocupado; cancelar y expirar liberan; el asiento liberado se reusa" do
      flight = new_flight()

      # Confirmar deja el asiento ocupado.
      {:ok, {flight, _}} = Flight.reserve_seat(flight, "1", "u", "r_confirm", now())
      {:ok, flight} = Flight.confirm(flight, "r_confirm")
      assert flight.seats["1"].status == :confirmed

      # Cancelar libera el asiento.
      {:ok, {flight, _}} = Flight.reserve_seat(flight, "2", "u", "r_cancel", now())
      {:ok, flight} = Flight.cancel(flight, "r_cancel")
      assert flight.seats["2"].status == :free

      # Expirar libera el asiento.
      {:ok, {flight, _}} = Flight.reserve_seat(flight, "3", "u", "r_expire", now())
      {:ok, flight} = Flight.expire(flight, "r_expire")
      assert flight.seats["3"].status == :free

      # Un asiento liberado se puede volver a reservar.
      assert {:ok, {_flight, _}} = Flight.reserve_seat(flight, "2", "u2", "r_again", now())
    end
  end
end
