defmodule Booking.Seat do
  @moduledoc """
  Asiento de un vuelo. Es solo una estructura de datos: su estado lo gobierna
  `Booking.Flight` (única fuente de verdad del vuelo).

  Estados posibles:

    * `:free`      — disponible.
    * `:reserved`  — tiene una reserva pendiente encima.
    * `:confirmed` — reserva confirmada; asignación definitiva.
  """

  @enforce_keys [:id]
  defstruct [:id, :held_by, status: :free]

  @type status :: :free | :reserved | :confirmed

  @type t :: %__MODULE__{
          id: String.t(),
          status: status(),
          held_by: String.t() | nil
        }

  @doc "Crea un asiento libre con el `id` dado."
  @spec new(String.t()) :: t()
  def new(id), do: %__MODULE__{id: id, status: :free, held_by: nil}
end
