# Protocolo WebSocket

> Mensajes entre el frontend (React) y el backend (Elixir/Cowboy). Una sola conexión
> WebSocket por cliente. Todos los mensajes son **JSON** con un campo `type` que los
> discrimina. Este documento es el contrato a estabilizar **antes** de codear el frontend.

## Convenciones

- **Sobre común:** todo mensaje es un objeto con `type` (string). El resto de los campos
  dependen del tipo.
- **Correlación opcional (`ref`):** el cliente puede incluir `"ref"` (string que él elige);
  el servidor lo **espeja** en la respuesta directa a ese pedido, para que el cliente
  empareje pedido↔respuesta. Los mensajes *empujados* (broadcasts) **no** llevan `ref`.
- **Identidad:** tras `register`, el cliente queda asociado a un `user_id` **en su proceso
  de conexión** (el backend lo recuerda; el cliente no lo reenvía en cada mensaje).
- **Estados** (`seat.status`, `reservation.status`): los mismos atoms del dominio,
  serializados como string (`"free"`, `"reserved"`, `"confirmed"`, `"pending"`,
  `"cancelled"`, `"expired"`).

---

## Cliente → Servidor

### `register`
Registra/recupera un usuario por nombre y lo asocia a esta conexión.
```json
{ "type": "register", "name": "Ana", "ref": "r1" }
```

### `list_flights`
Lista/busca/ordena vuelos. Todos los filtros son opcionales.
```json
{ "type": "list_flights", "date": "2026-07-20", "destination": "BRC", "sort": "price_asc", "ref": "r2" }
```
- `date`: filtra por fecha de salida (YYYY-MM-DD).
- `destination`: filtra por `code` de aeropuerto destino.
- `sort`: `"price_asc"` | `"price_desc"` (orden por precio).

### `open_flight`
Pide el detalle de un vuelo **y suscribe** esta conexión a sus actualizaciones en vivo.
```json
{ "type": "open_flight", "flight_id": "AR1001", "ref": "r3" }
```

### `close_flight`
Cancela la suscripción (el usuario salió del detalle).
```json
{ "type": "close_flight", "flight_id": "AR1001" }
```

### `reserve_seat`
Inicia una reserva `pending` sobre un asiento. Arranca el timer de 1 minuto.
```json
{ "type": "reserve_seat", "flight_id": "AR1001", "seat_id": "12A", "ref": "r4" }
```

### `pay`
Dispara el pago simulado (1-5 s en el backend). Si al terminar la reserva sigue `pending`,
se confirma.
```json
{ "type": "pay", "reservation_id": "res_abc", "ref": "r5" }
```

### `cancel`
Cancela una reserva que siga `pending`.
```json
{ "type": "cancel", "reservation_id": "res_abc", "ref": "r6" }
```

### `my_reservations`
Pide todas las reservas del usuario, en todos sus estados.
```json
{ "type": "my_reservations", "ref": "r7" }
```

---

## Servidor → Cliente

### `registered`
Respuesta a `register`.
```json
{ "type": "registered", "user_id": "user_01", "name": "Ana", "ref": "r1" }
```

### `flights`
Respuesta a `list_flights`. Info estática suficiente para el listado.
```json
{
  "type": "flights",
  "ref": "r2",
  "flights": [
    {
      "id": "AR1001",
      "airline": "Cóndor del Sur",
      "origin": "AEP",
      "destination": "BRC",
      "departs_at": "2026-07-20T08:30:00Z",
      "price": 185000,
      "seat_count": 60
    }
  ]
}
```

### `flight_detail`
Respuesta a `open_flight`. Incluye el estado **actual** de los asientos.
```json
{
  "type": "flight_detail",
  "ref": "r3",
  "flight": {
    "id": "AR1001",
    "airline": "Cóndor del Sur",
    "origin": "AEP",
    "destination": "BRC",
    "departs_at": "2026-07-20T08:30:00Z",
    "price": 185000
  },
  "seats": [
    { "id": "1A", "status": "free" },
    { "id": "1B", "status": "confirmed" },
    { "id": "12A", "status": "reserved" }
  ]
}
```

### `reservation_started`
Respuesta exitosa a `reserve_seat`.
```json
{
  "type": "reservation_started",
  "ref": "r4",
  "reservation_id": "res_abc",
  "flight_id": "AR1001",
  "seat_id": "12A",
  "expires_at": "2026-07-20T08:31:00Z"
}
```

### `reservation_update`
Cambio de estado de **una reserva propia** (resultado de `pay`/`cancel`/expiración).
```json
{ "type": "reservation_update", "reservation_id": "res_abc", "status": "confirmed" }
```
`status` puede ser `"confirmed"`, `"cancelled"` o `"expired"`. (Cuando es respuesta directa
a un `pay`/`cancel`, lleva el `ref` correspondiente; cuando es por expiración, no lleva `ref`.)

### `seat_update` (broadcast)
**Empujado a todas las conexiones suscriptas al vuelo** cuando cambia un asiento. Es lo que
mantiene sincronizados a varios clientes mirando el mismo vuelo.
```json
{ "type": "seat_update", "flight_id": "AR1001", "seat_id": "12A", "status": "confirmed" }
```

### `my_reservations`
Respuesta a `my_reservations`.
```json
{
  "type": "my_reservations",
  "ref": "r7",
  "reservations": [
    {
      "id": "res_abc",
      "flight_id": "AR1001",
      "seat_id": "12A",
      "status": "confirmed",
      "created_at": "2026-07-20T08:30:00Z",
      "expires_at": "2026-07-20T08:31:00Z"
    }
  ]
}
```

### `error`
Cualquier pedido que no se puede cumplir. Lleva el `ref` del pedido que falló (si lo tenía).
```json
{ "type": "error", "ref": "r4", "reason": "seat_taken" }
```

**`reason` posibles (no exhaustivo):**

| reason | cuándo |
|--------|--------|
| `not_registered` | se pidió una operación sin haber hecho `register` |
| `flight_not_found` | el `flight_id` no existe |
| `seat_not_found` | el `seat_id` no existe en ese vuelo |
| `seat_taken` | el asiento ya está `reserved`/`confirmed` (lo ganó otro) |
| `reservation_not_found` | el `reservation_id` no existe |
| `not_pending` | se intentó `pay`/`cancel` sobre una reserva ya finalizada |
| `not_owner` | la reserva no pertenece a este usuario |
| `invalid_message` | JSON malformado o `type` desconocido |

---

## Ejemplos de flujo

### A) Reserva exitosa
```
→ register {name:"Ana"}                 ← registered {user_id}
→ list_flights {sort:"price_asc"}        ← flights [...]
→ open_flight {flight_id:"AR1001"}       ← flight_detail {seats:[...]}
→ reserve_seat {seat_id:"12A"}           ← reservation_started {reservation_id, expires_at}
                                         ⇐ seat_update {12A:"reserved"}  (a todos los suscriptos)
→ pay {reservation_id}                   ← reservation_update {confirmed}   (tras 1-5 s)
                                         ⇐ seat_update {12A:"confirmed"} (a todos)
```

### B) Dos usuarios, mismo asiento (concurrencia)
```
Ana  → reserve_seat 12A   ← reservation_started   (ganó)
Beto → reserve_seat 12A   ← error {reason:"seat_taken"}   (perdió)
```

### C) Expiración durante el pago (edge case)
```
→ reserve_seat 12A    ← reservation_started {expires_at}
   (pasan 60 s sin pagar)
                      ← reservation_update {expired}   (empujado, sin ref)
                      ⇐ seat_update {12A:"free"}
→ pay {reservation_id} ← error {reason:"not_pending"}   (el pago llegó tarde)
```
