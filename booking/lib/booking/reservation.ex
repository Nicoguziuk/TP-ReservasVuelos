defmodule Booking.Reservation do
  @moduledoc """
  Reserva de un asiento por un usuario. Es solo una estructura de datos; las
  transiciones de estado las hace `Booking.Flight`.

  Una reserva nace `:pending` y termina en un único estado final:
  `:confirmed`, `:cancelled` o `:expired`.
  """

  # Plazo por defecto: 1 minuto, en ms (para Process.send_after del FlightServer).
  @default_ttl_ms 60_000

  @enforce_keys [:id, :flight_id, :seat_id, :user_id, :created_at, :expires_at]
  defstruct [
    :id,
    :flight_id,
    :seat_id,
    :user_id,
    :created_at,
    :expires_at,
    status: :pending
  ]

  @type status :: :pending | :confirmed | :cancelled | :expired

  @type t :: %__MODULE__{
          id: String.t(),
          flight_id: String.t(),
          seat_id: String.t(),
          user_id: String.t(),
          status: status(),
          created_at: DateTime.t(),
          expires_at: DateTime.t()
        }

  @doc "Crea una reserva pending con expires_at = now + ttl_ms. now y ttl_ms se pasan por parámetro para que sea testeable."
  @spec new(String.t(), String.t(), String.t(), String.t(), DateTime.t(), pos_integer()) :: t()
  def new(id, flight_id, seat_id, user_id, %DateTime{} = now, ttl_ms) do
    %__MODULE__{
      id: id,
      flight_id: flight_id,
      seat_id: seat_id,
      user_id: user_id,
      status: :pending,
      created_at: now,
      expires_at: DateTime.add(now, ttl_ms, :millisecond)
    }
  end

  @doc "Plazo por defecto (en milisegundos) de una reserva pendiente: 1 minuto."
  @spec default_ttl_ms() :: pos_integer()
  def default_ttl_ms, do: @default_ttl_ms
end
