defmodule Booking.SeedTest do
  use ExUnit.Case, async: true

  alias Booking.{Boot, Persistence, Seed}

  test "el catálogo tiene 5 aerolíneas, >= 10 vuelos c/u (>= 50 total) y datos válidos" do
    flights = Seed.flights()

    assert length(flights) >= 50

    by_airline = Enum.group_by(flights, & &1.airline_id)
    assert map_size(by_airline) == 5
    assert Enum.all?(by_airline, fn {_code, fs} -> length(fs) >= 10 end)

    # Cada vuelo: 20–100 asientos, origen != destino, precio > 0.
    assert Enum.all?(flights, fn f -> map_size(f.seats) in 20..100 end)
    assert Enum.all?(flights, fn f -> f.origin != f.destination end)
    assert Enum.all?(flights, fn f -> f.price > 0 end)

    # Ids únicos.
    ids = Enum.map(flights, & &1.id)
    assert length(Enum.uniq(ids)) == length(ids)
  end

  @tag :tmp_dir
  test "el seed corre solo con DETS vacío y no duplica al reiniciar", %{tmp_dir: tmp_dir} do
    p = :"persistence_#{System.unique_integer([:positive])}"
    start_supervised!({Persistence, name: p, dir: tmp_dir})

    assert Persistence.get_flights(p) == []

    # Primer boot (DETS vacío) → siembra.
    :ok = Boot.seed_if_empty(p)
    n1 = length(Persistence.get_flights(p))
    assert n1 >= 50

    # Segundo boot (ya hay datos) → no siembra de nuevo (idempotente).
    :ok = Boot.seed_if_empty(p)
    n2 = length(Persistence.get_flights(p))
    assert n2 == n1
  end
end
