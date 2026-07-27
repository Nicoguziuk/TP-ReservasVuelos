// Vista "Mis reservas": muestra todas las reservas del usuario con su estado.
export default function MyReservations({ reservations }) {
  if (reservations.length === 0) {
    return <p className="muted">No tenés reservas todavía.</p>;
  }

  return (
    <ul className="flights">
      {reservations.map((r) => (
        <li key={r.id} className="card flight">
          <div className="flight-info">
            Vuelo {r.flight_id} · asiento {r.seat_id}
            <br />
            <span className="muted">{r.id}</span>
          </div>
          <span className={`status ${r.status}`}>{statusLabel(r.status)}</span>
        </li>
      ))}
    </ul>
  );
}

function statusLabel(status) {
  return (
    {
      pending: "Pendiente",
      confirmed: "Confirmada",
      cancelled: "Cancelada",
      expired: "Expirada",
    }[status] || status
  );
}