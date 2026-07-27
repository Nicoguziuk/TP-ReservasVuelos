defmodule Booking.PersistenceTest do
  use ExUnit.Case, async: true

  alias Booking.{Persistence, Reservation}

  # Cada test arranca su propio Persistence con nombre único y carpeta temporal (tag
  # :tmp_dir de ExUnit) → aislado, sin tocar el disco real ni pisarse entre tests async.
  defp start_persistence(tmp_dir) do
    name = :"persistence_#{System.unique_integer([:positive])}"
    start_supervised!({Persistence, name: name, dir: tmp_dir})
    name
  end

  defp reservation(id) do
    Reservation.new(id, "AR1001", "1", "ana", ~U[2026-07-20 08:00:00Z], 60_000)
  end

  @tag :tmp_dir
  test "guarda una reserva y la recupera", %{tmp_dir: tmp_dir} do
    p = start_persistence(tmp_dir)

    assert Persistence.get_reservations(p) == []
    assert :ok = Persistence.put_reservation(reservation("AR1001-r1"), p)

    assert [res] = Persistence.get_reservations(p)
    assert res.id == "AR1001-r1"
    assert res.status == :pending
  end

  @tag :tmp_dir
  test "put con el mismo id sobrescribe (no duplica)", %{tmp_dir: tmp_dir} do
    p = start_persistence(tmp_dir)

    res = reservation("AR1001-r1")
    :ok = Persistence.put_reservation(res, p)
    :ok = Persistence.put_reservation(%{res | status: :confirmed}, p)

    assert [stored] = Persistence.get_reservations(p)
    assert stored.status == :confirmed
  end
end
