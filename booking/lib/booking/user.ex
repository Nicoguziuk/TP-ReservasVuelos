defmodule Booking.User do
  @moduledoc """
  Usuario registrado del sistema. Identidad simple por nombre, sin password:
  el enunciado no pide autenticación real, y agregarla sería complejidad de más
  para lo que este TP necesita (ver docs/DECISIONES.md, C2).

  El `id` lo genera el proceso que crea usuarios (no `Booking.User` en sí: generar
  un id es un efecto no determinista, igual que con `Reservation`), y es lo que
  ata las reservas a un usuario concreto.
  """

  @enforce_keys [:id, :name]
  defstruct [:id, :name]

  @type t :: %__MODULE__{id: String.t(), name: String.t()}
end