defmodule Booking.FlightServer do
  @moduledoc """
  GenServer que representa un vuelo. Es la capa con efectos alrededor del dominio puro
  `Booking.Flight`: genera el reservation_id y el timestamp, serializa las operaciones
  (todo entra por GenServer.call así que no hay dos reservas peleando el mismo asiento),
  maneja la expiración con timers (re-validando contra el dominio, no confiando en el
  timer), persiste cada cambio si hay backend configurado, simula el pago con una Task
  async, y avisa a los suscriptos por broadcast cuando algo cambia.

  Estado: flight, seq (para los ids), ttl_ms, persistence, timers, payments, subscribers.
  """

  use GenServer

  alias Booking.{Flight, Persistence, Reservation}

  # --- API de cliente ---

  @doc """
  Arranca el proceso. opts requiere :flight, y opcionalmente acepta :name, :ttl_ms,
  :persistence y :reservations (para reconstruir el estado al bootear).
  """
  def start_link(opts) do
    {flight, opts} = Keyword.pop!(opts, :flight)
    {ttl_ms, opts} = Keyword.pop(opts, :ttl_ms, Reservation.default_ttl_ms())
    {persistence, opts} = Keyword.pop(opts, :persistence, nil)
    {reservations, opts} = Keyword.pop(opts, :reservations, [])
    GenServer.start_link(__MODULE__, {flight, ttl_ms, persistence, reservations}, opts)
  end

  @doc "Inicia una reserva pendiente sobre `seat_id` para `user_id`."
  @spec reserve_seat(GenServer.server(), String.t(), String.t()) ::
          {:ok, Reservation.t()} | {:error, :seat_not_found | :seat_taken}
  def reserve_seat(server, seat_id, user_id) do
    GenServer.call(server, {:reserve_seat, seat_id, user_id})
  end

  @doc "Confirma (paga) una reserva pendiente."
  @spec confirm(GenServer.server(), String.t()) ::
          {:ok, Reservation.t()} | {:error, :reservation_not_found | :not_pending}
  def confirm(server, reservation_id) do
    GenServer.call(server, {:confirm, reservation_id})
  end

  @doc "Cancela una reserva pendiente del usuario `user_id` (debe ser suya)."
  @spec cancel(GenServer.server(), String.t(), String.t()) ::
          {:ok, Reservation.t()}
          | {:error, :reservation_not_found | :not_owner | :not_pending}
  def cancel(server, reservation_id, user_id) do
    GenServer.call(server, {:cancel, reservation_id, user_id})
  end

  @doc """
  Inicia el pago simulado de una reserva pendiente (asíncrono, devuelve {:ok, :processing}).
  opts admite :force y :delay para tests.
  """
  @spec pay(GenServer.server(), String.t(), String.t(), keyword()) ::
          {:ok, :processing}
          | {:error, :reservation_not_found | :not_owner | :not_pending | :payment_in_progress}
  def pay(server, reservation_id, user_id, opts \\ []) do
    GenServer.call(server, {:pay, reservation_id, user_id, opts})
  end

  @doc "Devuelve el `%Booking.Flight{}` actual (inspección / detalle del vuelo)."
  @spec get_flight(GenServer.server()) :: Flight.t()
  def get_flight(server), do: GenServer.call(server, :get_flight)

  @doc "Suscribe `pid` a las actualizaciones del vuelo (recibirá `{:push, mensaje}`)."
  @spec subscribe(GenServer.server(), pid()) :: :ok
  def subscribe(server, pid), do: GenServer.cast(server, {:subscribe, pid})

  @doc "Desuscribe `pid` de las actualizaciones del vuelo."
  @spec unsubscribe(GenServer.server(), pid()) :: :ok
  def unsubscribe(server, pid), do: GenServer.cast(server, {:unsubscribe, pid})

  # --- Callbacks ---

  @impl true
  def init({%Flight{} = flight, ttl_ms, persistence, reservations}) do
    now = DateTime.utc_now()
    {flight, arms, expired} = Flight.load(flight, reservations, now)

    # Re-arma los timers de las pending vigentes con el tiempo que les queda.
    timers =
      Map.new(arms, fn {reservation_id, remaining_ms} ->
        {reservation_id, Process.send_after(self(), {:expire, reservation_id}, remaining_ms)}
      end)

    state = %{
      flight: flight,
      seq: next_seq(reservations),
      ttl_ms: ttl_ms,
      persistence: persistence,
      timers: timers,
      payments: MapSet.new(),
      subscribers: %{}
    }

    # Persistimos las que vencieron mientras el server estaba apagado (sin notify, todavía no hay suscriptos).
    Enum.each(expired, fn reservation -> persist(state, reservation) end)

    {:ok, state}
  end

  @impl true
  def handle_call({:reserve_seat, seat_id, user_id}, _from, state) do
    reservation_id = "#{state.flight.id}-r#{state.seq}"
    now = DateTime.utc_now()

    case Flight.reserve_seat(state.flight, seat_id, user_id, reservation_id, now, state.ttl_ms) do
      {:ok, {flight, reservation}} ->
        # Programa la auto-expiración de la reserva.
        timer_ref = Process.send_after(self(), {:expire, reservation_id}, state.ttl_ms)

        state = %{
          state
          | flight: flight,
            seq: state.seq + 1,
            timers: Map.put(state.timers, reservation_id, timer_ref)
        }

        notify(state, reservation)
        {:reply, {:ok, reservation}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:confirm, reservation_id}, _from, state) do
    reply_transition(Flight.confirm(state.flight, reservation_id), reservation_id, state)
  end

  @impl true
  def handle_call({:cancel, reservation_id, user_id}, _from, state) do
    case Map.get(state.flight.reservations, reservation_id) do
      nil ->
        {:reply, {:error, :reservation_not_found}, state}

      %Reservation{user_id: owner} when owner != user_id ->
        {:reply, {:error, :not_owner}, state}

      %Reservation{} ->
        reply_transition(Flight.cancel(state.flight, reservation_id), reservation_id, state)
    end
  end

  @impl true
  def handle_call({:pay, reservation_id, user_id, opts}, _from, state) do
    case Map.get(state.flight.reservations, reservation_id) do
      nil ->
        {:reply, {:error, :reservation_not_found}, state}

      %Reservation{user_id: owner} when owner != user_id ->
        {:reply, {:error, :not_owner}, state}

      %Reservation{status: status} when status != :pending ->
        {:reply, {:error, :not_pending}, state}

      %Reservation{} ->
        if MapSet.member?(state.payments, reservation_id) do
          # Doble-pay: ya hay una Task de pago en vuelo para esta reserva.
          {:reply, {:error, :payment_in_progress}, state}
        else
          start_payment_task(self(), reservation_id, opts)
          state = %{state | payments: MapSet.put(state.payments, reservation_id)}
          {:reply, {:ok, :processing}, state}
        end
    end
  end

  @impl true
  def handle_call(:get_flight, _from, state) do
    {:reply, state.flight, state}
  end

  @impl true
  def handle_cast({:subscribe, pid}, state) do
    if Map.has_key?(state.subscribers, pid) do
      {:noreply, state}
    else
      ref = Process.monitor(pid)
      {:noreply, %{state | subscribers: Map.put(state.subscribers, pid, ref)}}
    end
  end

  @impl true
  def handle_cast({:unsubscribe, pid}, state) do
    {:noreply, remove_subscriber(state, pid)}
  end

  @impl true
  def handle_info({:expire, reservation_id}, state) do
    # Saca el timer ya disparado del estado.
    state = %{state | timers: Map.delete(state.timers, reservation_id)}

    # Re-valida contra el dominio: si ya no está pending, no hace nada.
    case Flight.expire(state.flight, reservation_id) do
      {:ok, %Flight{} = flight} ->
        state = %{state | flight: flight}
        notify(state, Map.fetch!(flight.reservations, reservation_id))
        {:noreply, state}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:payment_result, reservation_id, result}, state) do
    state = %{state | payments: MapSet.delete(state.payments, reservation_id)}
    {:noreply, apply_payment(result, reservation_id, state)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Se cayó la conexión de un suscriptor: lo sacamos de la lista.
    {:noreply, remove_subscriber(state, pid)}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  # Pago aprobado: confirma solo si la reserva sigue pending (si ya expiró/canceló, no pasa nada).
  defp apply_payment(:ok, reservation_id, state) do
    case Flight.confirm(state.flight, reservation_id) do
      {:ok, %Flight{} = flight} ->
        {_reservation, state} = apply_ok(flight, reservation_id, state)
        state

      {:error, _reason} ->
        state
    end
  end

  # Pago rechazado: la reserva sigue :pending (su timer sigue corriendo hasta vencer).
  defp apply_payment(:error, _reservation_id, state), do: state

  # Simula el pago: espera un delay random y devuelve ok/error. No confirma, solo avisa.
  defp start_payment_task(flight_server, reservation_id, opts) do
    delay = Keyword.get(opts, :delay, Enum.random(1000..5000))
    result = Keyword.get(opts, :force) || payment_result()

    Task.Supervisor.start_child(Booking.PaymentSupervisor, fn ->
      Process.sleep(delay)
      send(flight_server, {:payment_result, reservation_id, result})
    end)
  end

  defp payment_result do
    if :rand.uniform() <= Application.get_env(:booking, :payment_success_rate, 1.0),
      do: :ok,
      else: :error
  end

  # Traduce el resultado de una transición pura (confirm/cancel) a la respuesta del cliente.
  defp reply_transition({:ok, %Flight{} = flight}, reservation_id, state) do
    {reservation, state} = apply_ok(flight, reservation_id, state)
    {:reply, {:ok, reservation}, state}
  end

  defp reply_transition({:error, reason}, _reservation_id, state) do
    {:reply, {:error, reason}, state}
  end

  # Aplica un confirm/cancel exitoso: actualiza el flight, cancela el timer y persiste.
  defp apply_ok(%Flight{} = flight, reservation_id, state) do
    reservation = Map.fetch!(flight.reservations, reservation_id)
    state = %{state | flight: flight, timers: cancel_timer(state.timers, reservation_id)}
    notify(state, reservation)
    {reservation, state}
  end

  # Cancela el timer si existe. Es solo optimización, igual se re-valida en handle_info.
  defp cancel_timer(timers, reservation_id) do
    case Map.pop(timers, reservation_id) do
      {nil, timers} ->
        timers

      {timer_ref, timers} ->
        Process.cancel_timer(timer_ref)
        timers
    end
  end

  # Guarda la reserva antes de responder al cliente. Sin backend configurado, no hace nada.
  defp persist(%{persistence: nil}, _reservation), do: :ok

  defp persist(%{persistence: persistence}, %Reservation{} = reservation) do
    Persistence.put_reservation(reservation, persistence)
  end

  # Persiste y avisa a los suscriptos, todo junto para no olvidarse de ninguno.
  defp notify(state, %Reservation{} = reservation) do
    persist(state, reservation)
    seat = Map.fetch!(state.flight.seats, reservation.seat_id)

    broadcast(state, %{
      type: "seat_update",
      flight_id: state.flight.id,
      seat_id: seat.id,
      status: to_string(seat.status)
    })

    # reservation_update solo en estados finales; el cliente filtra por su propio reservation_id.
    if reservation.status != :pending do
      broadcast(state, %{
        type: "reservation_update",
        reservation_id: reservation.id,
        status: to_string(reservation.status)
      })
    end

    :ok
  end

  defp broadcast(state, message) do
    Enum.each(state.subscribers, fn {pid, _ref} -> send(pid, {:push, message}) end)
  end

  # Saca un suscriptor (si está) y demonitorea. Idempotente.
  defp remove_subscriber(state, pid) do
    case Map.pop(state.subscribers, pid) do
      {nil, _subscribers} ->
        state

      {ref, subscribers} ->
        Process.demonitor(ref, [:flush])
        %{state | subscribers: subscribers}
    end
  end

  # Siguiente número de reserva: max de las persistidas + 1, para no repetir ids.
  defp next_seq(reservations) do
    reservations
    |> Enum.map(fn %{id: id} ->
      case id |> String.split("-r") |> List.last() |> Integer.parse() do
        {n, _rest} -> n
        :error -> 0
      end
    end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end
end
