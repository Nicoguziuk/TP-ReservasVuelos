defmodule Booking.Seed do
  @moduledoc """
  Datos iniciales del sistema (vuelos de cabotaje en Argentina). Genera de forma
  **determinista** (sin azar) el catálogo: 5 aerolíneas ficticias × 12 vuelos = 60 vuelos,
  entre aeropuertos nacionales reales, con asientos (20-100), precios y fechas realistas.

  Determinista a propósito: así el catálogo es el mismo en cada `mix test` y en cada
  primer arranque, sin sorpresas para la demo ni para los tests que dependen de cantidades
  fijas (ver `Booking.Boot`).

  `flights/0` devuelve esqueletos `%Booking.Flight{}` (asientos `:free`, sin reservas).
  Lo usa `Booking.Boot` para sembrar la tabla `flights` de Persistence cuando está vacía.
  Las fechas se generan **relativas a hoy** (`Date.utc_today/0`), para que los vuelos
  sembrados queden siempre a futuro sin importar cuándo se corra el seed.
  """

  alias Booking.Flight

  # Aeropuertos nacionales (códigos IATA reales) {código, ciudad}.
  @airports [
    {"AEP", "Buenos Aires"},
    {"EZE", "Buenos Aires"},
    {"COR", "Córdoba"},
    {"MDZ", "Mendoza"},
    {"BRC", "Bariloche"},
    {"ROS", "Rosario"},
    {"SLA", "Salta"},
    {"IGR", "Puerto Iguazú"},
    {"USH", "Ushuaia"},
    {"FTE", "El Calafate"},
    {"NQN", "Neuquén"},
    {"TUC", "Tucumán"}
  ]

  # Aerolíneas ficticias {código, nombre}. El nombre es lo único que se muestra
  # en la UI (Protocol lo mapea desde el airline_id al armar la respuesta JSON).
  @airlines [
    {"CDS", "Cóndor del Sur"},
    {"PMP", "Aerolíneas Pampa"},
    {"PTG", "Aero Patagonia"},
    {"SUR", "Sur Andino"},
    {"LIT", "Litoral Express"}
  ]

  @flights_per_airline 12
  @seat_sizes [48, 72, 96]
  @departure_hours [8, 11, 14, 18, 21]

  @doc "Aerolíneas del sistema: lista de `{código, nombre}`."
  @spec airlines() :: [{String.t(), String.t()}]
  def airlines, do: @airlines

  @doc "Aeropuertos del sistema: lista de `{código, ciudad}`."
  @spec airports() :: [{String.t(), String.t()}]
  def airports, do: @airports

  @doc "Catálogo inicial de vuelos (esqueletos `%Booking.Flight{}`), determinista."
  @spec flights() :: [Flight.t()]
  def flights do
    total = length(@airlines) * @flights_per_airline
    Enum.map(0..(total - 1), &build_flight/1)
  end

  # Arma el vuelo número `i` (0-indexado, 0..59). Todo lo que varía entre vuelos
  # se deriva de `i` con aritmética simple: nada de azar, para que el catálogo
  # sea reproducible entre corridas.
  defp build_flight(i) do
    {airline_code, _name} = Enum.at(@airlines, div(i, @flights_per_airline))
    number = rem(i, @flights_per_airline) + 1
    n = length(@airports)

    Flight.new(%{
      id: "#{airline_code}#{100 + number}",
      airline_id: airline_code,
      origin: airport_code(rem(i, n)),
      # Offset de +5 (no arbitrario del todo: > 0 y < n) garantiza destino != origen
      # para cualquier i, sin tener que chequearlo en runtime.
      destination: airport_code(rem(i + 5 + div(i, @flights_per_airline), n)),
      departs_at: departs_at(i),
      price: 80_000 + rem(i * 7, 25) * 9_000,
      seat_count: Enum.at(@seat_sizes, rem(i, 3))
    })
  end

  defp airport_code(idx), do: elem(Enum.at(@airports, idx), 0)

  # Fecha relativa a hoy (dentro de los próximos 30 días) + hora fija de una lista corta,
  # para que siempre queden vuelos "a futuro" sin importar cuándo se corra el seed.
  defp departs_at(i) do
    date = Date.add(Date.utc_today(), rem(i, 30))
    time = Time.new!(Enum.at(@departure_hours, rem(i, 5)), 0, 0)
    DateTime.new!(date, time)
  end
end