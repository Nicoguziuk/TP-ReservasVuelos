import { useMemo, useState } from "react";

// Búsqueda/listado: filtra por fecha y destino y ordena por precio, todo client-side
// (useMemo) sobre el catálogo ya traído. 
export default function SearchView({ flights, onOpen }) {
  const [date, setDate] = useState("");
  const [destination, setDestination] = useState("");
  const [sort, setSort] = useState("");

  const destinations = useMemo(
    () => [...new Set(flights.map((f) => f.destination))].sort(),
    [flights],
  );

  const visible = useMemo(() => {
    let result = flights.filter((f) => {
      const matchDate = !date || f.departs_at.slice(0, 10) === date;
      const matchDest = !destination || f.destination === destination;
      return matchDate && matchDest;
    });

    if (sort === "price_asc") result = [...result].sort((a, b) => a.price - b.price);
    if (sort === "price_desc") result = [...result].sort((a, b) => b.price - a.price);

    return result;
  }, [flights, date, destination, sort]);

  return (
    <section>
      <div className="filters card">
        <label>
          Fecha
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </label>
        <label>
          Destino
          <select value={destination} onChange={(e) => setDestination(e.target.value)}>
            <option value="">Todos</option>
            {destinations.map((d) => (
              <option key={d} value={d}>
                {d}
              </option>
            ))}
          </select>
        </label>
        <label>
          Ordenar
          <select value={sort} onChange={(e) => setSort(e.target.value)}>
            <option value="">—</option>
            <option value="price_asc">Precio ↑</option>
            <option value="price_desc">Precio ↓</option>
          </select>
        </label>
        <button
          className="secondary"
          onClick={() => {
            setDate("");
            setDestination("");
            setSort("");
          }}
        >
          Limpiar
        </button>
      </div>

      {visible.length === 0 ? (
        <p className="muted">No hay vuelos para esa búsqueda.</p>
      ) : (
        <ul className="flights">
          {visible.map((f) => (
            <li key={f.id} className="card flight">
              <div className="flight-info">
                <strong>{f.airline}</strong> · {f.id}
                <br />
                {f.origin} → {f.destination}
                <br />
                <span className="muted">{formatDate(f.departs_at)}</span>
              </div>
              <div className="price">${f.price.toLocaleString("es-AR")}</div>
              <button onClick={() => onOpen(f.id)}>Ver asientos</button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function formatDate(iso) {
  return new Date(iso).toLocaleString("es-AR", { dateStyle: "short", timeStyle: "short" });
}