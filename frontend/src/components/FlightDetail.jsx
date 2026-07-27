import { useEffect, useState } from "react";

// Detalle del vuelo: datos + grilla de asientos (estados visuales) + flujo de reserva.
export default function FlightDetail({ state, actions }) {
  const { flight, seats } = state.flightDetail;
  const { reservation, selectedSeat, myReservations } = state;

  // OJO: comparar también el flight_id — si no, una reserva pendiente en OTRO vuelo
  // bloquea por error la selección de asientos acá (bug detectado en la auditoría).
  const hasPending =
    reservation && reservation.status === "pending" && reservation.flight_id === flight.id;

  // Asientos del usuario en este vuelo (pendientes o confirmados) → se marcan "tuyo".
  const ownSeatIds = new Set(
    myReservations
      .filter((r) => r.flight_id === flight.id && ["pending", "confirmed"].includes(r.status))
      .map((r) => r.seat_id),
  );
  if (reservation && reservation.flight_id === flight.id && reservation.status === "pending") {
    ownSeatIds.add(reservation.seat_id);
  }

  return (
    <section>
      <button className="back secondary" onClick={() => actions.setView("search")}>
        ← Volver
      </button>

      <h2>
        {flight.airline} · {flight.id}
      </h2>
      <p className="muted">
        {flight.origin} → {flight.destination} ·{" "}
        {new Date(flight.departs_at).toLocaleString("es-AR")} · $
        {flight.price.toLocaleString("es-AR")}
      </p>

      <ReservationPanel state={state} actions={actions} />

      <div className="legend">
        <span className="seat free">Disponible</span>
        <span className="seat reserved">Reservado</span>
        <span className="seat confirmed">Confirmado</span>
        <span className="seat own">Tuyo</span>
        <span className="seat selected">Elegido</span>
      </div>

      <div className="seatgrid">
        {seats.map((s) => {
          const own = ownSeatIds.has(s.id);
          const isSelected = selectedSeat === s.id;
          const className = ["seat", own ? "own" : s.status, isSelected ? "selected" : ""]
            .filter(Boolean)
            .join(" ");
          const clickable = s.status === "free" && !hasPending;

          return (
            <button
              key={s.id}
              className={className}
              disabled={!clickable}
              onClick={() => actions.selectSeat(isSelected ? null : s.id)}
              title={`Asiento ${s.id} (${s.status})`}
            >
              {s.id}
            </button>
          );
        })}
      </div>

      {selectedSeat && !hasPending && (
        <button className="reserve" onClick={() => actions.reserve(flight.id, selectedSeat)}>
          Reservar asiento {selectedSeat}
        </button>
      )}
    </section>
  );
}

// Panel del flujo de reserva: pendiente (contador + pagar/cancelar) → procesando →
// confirmado / rechazado(pendiente) / expirado.
function ReservationPanel({ state, actions }) {
  const { reservation, paying, flightDetail } = state;
  if (!reservation || reservation.flight_id !== flightDetail.flight.id) return null;

  if (reservation.status === "confirmed") {
    return (
      <div className="panel ok">
        ✅ Reserva confirmada (asiento {reservation.seat_id}).
        <button onClick={() => actions.setView("search")}>Buscar otro vuelo</button>
      </div>
    );
  }

  if (reservation.status === "expired") {
    return <div className="panel warn">⌛ La reserva expiró. Elegí otro asiento.</div>;
  }

  if (reservation.status === "cancelled") {
    return <div className="panel warn">Reserva cancelada.</div>;
  }

  // pending
  return (
    <div className="panel pending">
      <span>
        Reserva pendiente · asiento {reservation.seat_id} ·{" "}
        <Countdown expiresAt={reservation.expires_at} />
      </span>
      {paying ? (
        <span>⏳ Procesando pago…</span>
      ) : (
        <span className="actions">
          <button onClick={() => actions.pay(reservation.reservation_id)}>Pagar</button>
          <button className="secondary" onClick={() => actions.cancel(reservation.reservation_id)}>
            Cancelar
          </button>
        </span>
      )}
    </div>
  );
}

function Countdown({ expiresAt }) {
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  const ms = new Date(expiresAt).getTime() - now;
  if (ms <= 0) return <strong>0:00</strong>;

  const total = Math.floor(ms / 1000);
  const minutes = Math.floor(total / 60);
  const seconds = String(total % 60).padStart(2, "0");
  return (
    <strong>
      {minutes}:{seconds}
    </strong>
  );
}