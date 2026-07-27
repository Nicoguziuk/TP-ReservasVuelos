import { useEffect, useReducer, useRef } from "react";

// El backend escucha en este endpoint 
const WS_URL = "ws://localhost:4000/ws";

const initialState = {
  connected: false,
  user: null, // { user_id, name }
  flights: [], // catálogo (se trae una vez; el filtro/orden es client-side)
  flightDetail: null, // { flight, seats } del vuelo abierto
  myReservations: [],
  reservation: null, // flujo activo: { reservation_id, flight_id, seat_id, status, expires_at }
  paying: false,
  selectedSeat: null,
  view: "search", // "search" | "detail" | "reservations"
  error: null,
};

function reducer(state, action) {
  switch (action.type) {
    case "connected":
      return { ...state, connected: true };
    case "disconnected":
      return { ...state, connected: false };
    case "select_seat":
      return { ...state, selectedSeat: action.seatId };
    case "view":
      return { ...state, view: action.view, error: null };
    case "message":
      return handleMessage(state, action.message);
    default:
      return state;
  }
}

// Aplica un mensaje del servidor (respuesta o evento push) al estado de la UI.
function handleMessage(state, msg) {
  switch (msg.type) {
    case "registered":
      return { ...state, user: { user_id: msg.user_id, name: msg.name }, error: null };
    case "flights":
      return { ...state, flights: msg.flights };
    case "flight_detail":
      return {
        ...state,
        flightDetail: { flight: msg.flight, seats: msg.seats },
        view: "detail",
        selectedSeat: null,
        error: null,
      };
    case "reservation_started":
      return {
        ...state,
        reservation: {
          reservation_id: msg.reservation_id,
          flight_id: msg.flight_id,
          seat_id: msg.seat_id,
          status: "pending",
          expires_at: msg.expires_at,
        },
        paying: false,
        selectedSeat: null,
        error: null,
      };
    case "payment_started":
      return { ...state, paying: true, error: null };
    case "reservation_update":
      return applyReservationUpdate(state, msg);
    case "seat_update":
      return applySeatUpdate(state, msg);
    case "my_reservations":
      return { ...state, myReservations: msg.reservations };
    case "error":
      return { ...state, error: msg.reason, paying: false };
    default:
      return state;
  }
}

// reservation_update llega a todos los suscriptos; solo reaccionamos si es nuestra reserva.
function applyReservationUpdate(state, msg) {
  let next = state;

  if (state.reservation && state.reservation.reservation_id === msg.reservation_id) {
    next = {
      ...next,
      reservation: { ...state.reservation, status: msg.status },
      paying: false,
    };
  }

  const myReservations = state.myReservations.map((r) =>
    r.id === msg.reservation_id ? { ...r, status: msg.status } : r,
  );

  return { ...next, myReservations };
}

// seat_update: actualiza el asiento en la grilla si estamos viendo ese vuelo.
function applySeatUpdate(state, msg) {
  if (!state.flightDetail || state.flightDetail.flight.id !== msg.flight_id) return state;

  const seats = state.flightDetail.seats.map((s) =>
    s.id === msg.seat_id ? { ...s, status: msg.status } : s,
  );

  return { ...state, flightDetail: { ...state.flightDetail, seats } };
}

export function useBooking() {
  const [state, dispatch] = useReducer(reducer, initialState);
  const wsRef = useRef(null);

  useEffect(() => {
    const ws = new WebSocket(WS_URL);
    wsRef.current = ws;

    ws.onopen = () => dispatch({ type: "connected" });
    ws.onclose = () => dispatch({ type: "disconnected" });
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      dispatch({ type: "message", message });

      // Al registrarse, pedimos catálogo y reservas.
      if (message.type === "registered") {
        send({ type: "list_flights" });
        send({ type: "my_reservations" });
      }
    };

    return () => ws.close();
  }, []);

  function send(message) {
    const ws = wsRef.current;
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(message));
  }

  const actions = {
    register: (name) => send({ type: "register", name }),
    openFlight: (flightId) => send({ type: "open_flight", flight_id: flightId }),
    selectSeat: (seatId) => dispatch({ type: "select_seat", seatId }),
    reserve: (flightId, seatId) =>
      send({ type: "reserve_seat", flight_id: flightId, seat_id: seatId }),
    pay: (reservationId) => send({ type: "pay", reservation_id: reservationId }),
    cancel: (reservationId) => send({ type: "cancel", reservation_id: reservationId }),
    refreshReservations: () => send({ type: "my_reservations" }),
    setView: (view) => dispatch({ type: "view", view }),
  };

  return { state, actions };
}