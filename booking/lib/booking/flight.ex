defmodule Booking.Flight do
  @moduledoc """
  Vuelo: maneja asientos y reservas, y hace cumplir las reglas del dominio.

  Todo acá es puro (sin efectos ni estado compartido): recibe un vuelo y devuelve
  uno nuevo o un error. El id de reserva, el now y el ttl se pasan por parámetro
  para que sea fácil de testear; generarlos es trabajo del FlightServer.

  Reglas: un asiento no puede tener dos reservas activas, solo una reserva pending
  puede confirmarse/cancelarse/expirar, y confirmar ocupa el asiento mientras que
  cancelar o expirar lo liberan.
  """

  alias Booking.{Reservation, Seat}

  @enforce_keys [:id, :airline_id, :origin, :destination, :departs_at, :price]
  defstruct [
    :id,
    :airline_id,
    :origin,
    :destination,
    :departs_at,
    :price,
    seats: %{},
    reservations: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          airline_id: String.t(),
          origin: String.t(),
          destination: String.t(),
          departs_at: DateTime.t(),
          price: non_neg_integer(),
          seats: %{optional(String.t()) => Seat.t()},
          reservations: %{optional(String.t()) => Reservation.t()}
        }

  @doc "Crea un vuelo con seat_count asientos libres numerados 1..N (entre 20 y 100)."
  @spec new(map()) :: t()
  def new(%{seat_count: seat_count} = attrs) when seat_count in 20..100 do
    seats =
      Map.new(1..seat_count, fn n ->
        id = Integer.to_string(n)
        {id, Seat.new(id)}
      end)

    attrs =
      attrs
      |> Map.delete(:seat_count)
      |> Map.put(:seats, seats)

    struct!(__MODULE__, attrs)
  end

  @doc "Reserva seat_id para user_id. Falla si el asiento no existe o ya está tomado."
  @spec reserve_seat(t(), String.t(), String.t(), String.t(), DateTime.t(), pos_integer()) ::
          {:ok, {t(), Reservation.t()}} | {:error, :seat_not_found | :seat_taken}
  def reserve_seat(
        %__MODULE__{} = flight,
        seat_id,
        user_id,
        reservation_id,
        %DateTime{} = now,
        ttl_ms \\ Reservation.default_ttl_ms()
      ) do
    case Map.get(flight.seats, seat_id) do
      nil ->
        {:error, :seat_not_found}

      %Seat{status: :free} = seat ->
        reservation = Reservation.new(reservation_id, flight.id, seat_id, user_id, now, ttl_ms)
        seat = %Seat{seat | status: :reserved, held_by: reservation_id}
        flight = put_reservation_and_seat(flight, reservation, seat)
        {:ok, {flight, reservation}}

      %Seat{} ->
        {:error, :seat_taken}
    end
  end

  @doc "Confirma (paga) una reserva pendiente; el asiento queda ocupado. Falla si no existe o ya no está pending."
  @spec confirm(t(), String.t()) :: {:ok, t()} | {:error, :reservation_not_found | :not_pending}
  def confirm(%__MODULE__{} = flight, reservation_id) do
    with_pending_reservation(flight, reservation_id, fn %Reservation{} = reservation ->
      reservation = %Reservation{reservation | status: :confirmed}
      seat = occupy_seat(seat_of(flight, reservation))
      put_reservation_and_seat(flight, reservation, seat)
    end)
  end

  @doc "Cancela una reserva pendiente y libera el asiento. Mismos errores que confirm/2."
  @spec cancel(t(), String.t()) :: {:ok, t()} | {:error, :reservation_not_found | :not_pending}
  def cancel(%__MODULE__{} = flight, reservation_id) do
    with_pending_reservation(flight, reservation_id, fn %Reservation{} = reservation ->
      reservation = %Reservation{reservation | status: :cancelled}
      seat = free_seat(seat_of(flight, reservation))
      put_reservation_and_seat(flight, reservation, seat)
    end)
  end

  @doc "Expira una reserva pendiente (se venció el plazo) y libera el asiento. El cuándo lo decide el FlightServer; acá solo se aplica. Mismos errores que confirm/2."
  @spec expire(t(), String.t()) :: {:ok, t()} | {:error, :reservation_not_found | :not_pending}
  def expire(%__MODULE__{} = flight, reservation_id) do
    with_pending_reservation(flight, reservation_id, fn %Reservation{} = reservation ->
      reservation = %Reservation{reservation | status: :expired}
      seat = free_seat(seat_of(flight, reservation))
      put_reservation_and_seat(flight, reservation, seat)
    end)
  end

  @doc """
  Reconstruye el vuelo aplicando sus reservas persistidas (restore al bootear). Cada
  asiento queda marcado según su reserva activa (confirmed o pending vigente); el resto
  va solo al historial.

  Devuelve {flight, arms, expired}: arms son las pending vigentes (para re-armar sus
  timers) y expired las que vencieron mientras el proceso estaba apagado.
  """
  @spec load(t(), [Reservation.t()], DateTime.t()) ::
          {t(), [{String.t(), non_neg_integer()}], [Reservation.t()]}
  def load(%__MODULE__{} = flight, reservations, %DateTime{} = now) do
    Enum.reduce(reservations, {flight, [], []}, fn reservation, {flight, arms, expired} ->
      load_one(flight, reservation, now, arms, expired)
    end)
  end

  # --- Auxiliares privados ---

  # Aplica fun solo si la reserva existe y está pending.
  defp with_pending_reservation(flight, reservation_id, fun) do
    case Map.get(flight.reservations, reservation_id) do
      nil -> {:error, :reservation_not_found}
      %Reservation{status: :pending} = reservation -> {:ok, fun.(reservation)}
      %Reservation{} -> {:error, :not_pending}
    end
  end

  defp seat_of(flight, %Reservation{seat_id: seat_id}) do
    %Seat{} = Map.fetch!(flight.seats, seat_id)
  end

  defp occupy_seat(%Seat{} = seat), do: %Seat{seat | status: :confirmed}

  defp free_seat(%Seat{} = seat), do: %Seat{seat | status: :free, held_by: nil}

  defp put_reservation_and_seat(
         %__MODULE__{} = flight,
         %Reservation{} = reservation,
         %Seat{} = seat
       ) do
    %__MODULE__{
      flight
      | reservations: Map.put(flight.reservations, reservation.id, reservation),
        seats: Map.put(flight.seats, seat.id, seat)
    }
  end

  # Reconstruye una reserva persistida (usado por load/3).
  defp load_one(
         %__MODULE__{} = flight,
         %Reservation{status: :confirmed} = res,
         _now,
         arms,
         expired
       ) do
    {occupy(flight, res, :confirmed), arms, expired}
  end

  defp load_one(%__MODULE__{} = flight, %Reservation{status: :pending} = res, now, arms, expired) do
    remaining = DateTime.diff(res.expires_at, now, :millisecond)

    if remaining > 0 do
      {occupy(flight, res, :reserved), [{res.id, remaining} | arms], expired}
    else
      expired_res = %Reservation{res | status: :expired}
      {history(flight, expired_res), arms, [expired_res | expired]}
    end
  end

  defp load_one(%__MODULE__{} = flight, %Reservation{} = res, _now, arms, expired) do
    # :cancelled / :expired → solo historial, no toca el asiento.
    {history(flight, res), arms, expired}
  end

  # Guarda la reserva y marca el asiento como ocupado por ella.
  defp occupy(%__MODULE__{} = flight, %Reservation{} = res, seat_status) do
    seat = %Seat{seat_of(flight, res) | status: seat_status, held_by: res.id}
    put_reservation_and_seat(flight, res, seat)
  end

  # Guarda la reserva solo en el historial, sin tocar el asiento.
  defp history(%__MODULE__{} = flight, %Reservation{} = res) do
    %__MODULE__{flight | reservations: Map.put(flight.reservations, res.id, res)}
  end
end
