import { useState } from "react";
import { useBooking } from "./useBooking";
import SearchView from "./components/SearchView";
import FlightDetail from "./components/FlightDetail";
import MyReservations from "./components/MyReservations";
import "./index.css";

export default function App() {
  const { state, actions } = useBooking();

  if (!state.user) {
    return <Register connected={state.connected} onRegister={actions.register} />;
  }

  return (
    <div className="app">
      <header>
        <h1>✈️ Reservas de vuelos</h1>
        <nav>
          <button
            className={state.view === "search" ? "active" : ""}
            onClick={() => actions.setView("search")}
          >
            Buscar vuelos
          </button>
          <button
            className={state.view === "reservations" ? "active" : ""}
            onClick={() => {
              actions.refreshReservations();
              actions.setView("reservations");
            }}
          >
            Mis reservas
          </button>
          <span className="user">
            {state.user.name} {state.connected ? "🟢" : "🔴"}
          </span>
        </nav>
      </header>

      {state.error && <div className="error">⚠️ {state.error}</div>}

      <main>
        {state.view === "search" && <SearchView flights={state.flights} onOpen={actions.openFlight} />}
        {state.view === "detail" && state.flightDetail && (
          <FlightDetail state={state} actions={actions} />
        )}
        {state.view === "reservations" && <MyReservations reservations={state.myReservations} />}
      </main>
    </div>
  );
}

function Register({ connected, onRegister }) {
  const [name, setName] = useState("");

  return (
    <div className="register">
      <h1>✈️ Reservas de vuelos</h1>
      <p className="muted">{connected ? "Conectado al servidor" : "Conectando…"}</p>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (name.trim()) onRegister(name.trim());
        }}
      >
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Tu nombre" />
        <button type="submit" disabled={!connected || !name.trim()}>
          Entrar
        </button>
      </form>
    </div>
  );
}