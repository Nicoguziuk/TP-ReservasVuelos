# Documentación técnica: modelo, protocolo y decisiones

## Modelo de dominio

> Entidades del dominio, sus campos, sus estados y dónde viven / se persisten. Identificadores
> en inglés; el modelo se mantiene chico y con **una sola fuente de verdad** por dato.

### Resumen de dónde vive cada cosa

| Entidad | Estática/Dinámica | Dónde vive en memoria | ¿Se persiste en DETS? |
|---------|-------------------|------------------------|------------------------|
| `Airline` | estática | `Booking.Seed` (lista fija en código, sin proceso propio) | embebida con los vuelos / catálogo fijo |
| `Airport` | estática | `Booking.Seed` (lista fija en código, sin proceso propio) | catálogo fijo |
| `Flight` | estática | se lee on-demand de `Booking.Persistence`; cada vuelo activo también la tiene embebida en su `FlightServer` | sí (tabla `flights`) |
| `Seat` | dinámica | `FlightServer` del vuelo | **derivado** (no tiene tabla propia, ver abajo) |
| `Reservation` | dinámica | `FlightServer` del vuelo | sí (tabla `reservations`) |
| `User` | dinámica | se resuelve on-demand contra `Booking.Persistence` (sin proceso propio) | sí (tabla `users`) |

### Entidades

#### `User`
Usuario registrado del sistema.

| Campo | Tipo | Notas |
|-------|------|-------|
| `id` | string | identificador único (generado por el backend) |
| `name` | string | nombre con el que se registró |

> **A confirmar con el grupo:** por ahora el registro es **solo por nombre, sin password**
> (ver más abajo, sección «Decisiones de diseño», C2). Si más adelante se quiere, se
> agrega `email`/clave.

#### `Airline`
Aerolínea ficticia. El enunciado pide **5 aerolíneas**.

| Campo | Tipo | Notas |
|-------|------|-------|
| `id` | string | ej. `"condor"` |
| `name` | string | ej. `"Cóndor del Sur"` |

#### `Airport`
Aeropuerto nacional argentino (origen/destino de los vuelos).

| Campo | Tipo | Notas |
|-------|------|-------|
| `code` | string | ej. `"EZE"`, `"AEP"`, `"COR"`, `"BRC"` |
| `city` | string | ej. `"Buenos Aires"`, `"Córdoba"`, `"Bariloche"` |

#### `Flight`
Vuelo concreto. Su info es **inmutable** (no cambia durante la operación; lo que cambia son
los asientos/reservas). El enunciado pide **≥10 vuelos por aerolínea** y entre **20 y 100
asientos** por vuelo.

| Campo | Tipo | Notas |
|-------|------|-------|
| `id` | string | ej. `"AR1001"` (número de vuelo) |
| `airline_id` | string | referencia a `Airline` |
| `origin` | string | `code` de un `Airport` |
| `destination` | string | `code` de un `Airport` |
| `departs_at` | datetime (ISO 8601) | fecha y hora de salida |
| `price` | integer | precio en pesos (entero, para ordenar sin decimales) |
| `seat_count` | integer | 20..100; cuántos asientos tiene el vuelo |

#### `Seat`
Asiento de un vuelo. Vive dentro del `FlightServer`. **No tiene tabla propia en DETS**: su
estado se **deriva** de las reservas al reconstruir el vuelo (ver más abajo, sección
«Decisiones de diseño», C3).

| Campo | Tipo | Notas |
|-------|------|-------|
| `id` | string | ej. `"12A"` (o número `1..seat_count`) |
| `status` | atom | `:free` \| `:reserved` \| `:confirmed` |
| `held_by` | string \| nil | `reservation_id` que lo retiene (si `:reserved`/`:confirmed`) |

**Estados de un asiento:**

```
        reserve_seat                 pay (confirm)
:free ───────────────> :reserved ─────────────────> :confirmed
  ^                        │
  └──── cancel / expire ───┘
```

- `:free` → disponible.
- `:reserved` → tiene una reserva `:pending` encima (alguien lo está por pagar).
- `:confirmed` → reserva confirmada; asignación **definitiva**.

#### `Reservation`
Una reserva de un asiento por un usuario. Vive en el `FlightServer` del vuelo y se persiste
en la tabla `reservations`.

| Campo | Tipo | Notas |
|-------|------|-------|
| `id` | string | identificador único |
| `flight_id` | string | vuelo al que pertenece |
| `seat_id` | string | asiento reservado |
| `user_id` | string | dueño de la reserva |
| `status` | atom | `:pending` \| `:confirmed` \| `:cancelled` \| `:expired` |
| `created_at` | datetime | cuándo se inició |
| `expires_at` | datetime | `created_at` + 1 minuto |

> El `timer_ref` del `Process.send_after` **no** es parte de la reserva persistida: vive
> solo en el estado en memoria del `FlightServer` (un timer no tiene sentido tras reiniciar).

**Estados de una reserva (una reserva termina en UN único estado final):**

```
                  pay (1-5s) y sigue pending
        ┌──────────────────────────────────> :confirmed   (final)
        │
:pending┤
        ├── cancel (mientras pending) ──────> :cancelled   (final)
        │
        └── pasaron 60s sin confirmar ──────> :expired     (final)
```

Reglas de transición (las hace cumplir el `FlightServer`, atendiendo un mensaje por vez):
- Solo se puede `confirm` / `cancel` / `expire` una reserva que esté `:pending`.
- Un `confirm` que llega cuando la reserva **ya** está `:expired`/`:cancelled` **no hace
  nada** (un pago tardío no confirma).
- `:confirmed`, `:cancelled` y `:expired` son **finales**: no se vuelve a `:pending`.

### Invariantes del dominio (deben cumplirse SIEMPRE)

1. Un asiento no puede estar asignado a dos usuarios a la vez.
2. Reserva `:confirmed` ⇒ asiento `:confirmed` (definitivo). Reserva `:cancelled`/`:expired`
   ⇒ asiento `:free`.
3. Una reserva termina en un **único estado final**: `:pending` → `:confirmed` |
   `:cancelled` | `:expired`.
4. No se puede confirmar una reserva ya expirada o cancelada.
5. Si dos usuarios reservan el mismo asiento a la vez, **solo uno** lo consigue
   (lo garantiza la serialización en el `FlightServer`).
6. Tras apagar y reiniciar el servidor, no se pierden usuarios, vuelos ni reservas
   persistidas; el estado de los asientos se reconstruye coherente: las reservas
   `:pending` que todavía tenían tiempo re-arman su timer por lo que les quedaba, y las
   que ya habían vencido se cierran como `:expired` (ver más abajo, sección «Decisiones
   de diseño», D2).

### Relación con la persistencia

- `users`, `flights` y `reservations` se guardan en DETS (tablas clave-valor).
- El **estado de los asientos no se guarda aparte**: queda determinado por las reservas
  (`:confirmed` ocupa el asiento; el resto lo deja libre). Al levantar un `FlightServer` se
  carga el `Flight` (para saber `seat_count`) y sus reservas, y se reconstruye el mapa de
  asientos. Justificación de por qué esto cumple "persistir el estado de asientos" del
  enunciado: ver sección «Decisiones de diseño» (más abajo).


## Protocolo WebSocket

> Mensajes entre el frontend (React) y el backend (Elixir/Cowboy). Una sola conexión
> WebSocket por cliente. Todos los mensajes son **JSON** con un campo `type` que los
> discrimina. Este documento es el contrato a estabilizar **antes** de codear el frontend.

### Convenciones

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

### Cliente → Servidor

#### `register`
Registra/recupera un usuario por nombre y lo asocia a esta conexión.
```json
{ "type": "register", "name": "Ana", "ref": "r1" }
```

#### `list_flights`
Lista/busca/ordena vuelos. Todos los filtros son opcionales.
```json
{ "type": "list_flights", "date": "2026-07-20", "destination": "BRC", "sort": "price_asc", "ref": "r2" }
```
- `date`: filtra por fecha de salida (YYYY-MM-DD).
- `destination`: filtra por `code` de aeropuerto destino.
- `sort`: `"price_asc"` | `"price_desc"` (orden por precio).

#### `open_flight`
Pide el detalle de un vuelo **y suscribe** esta conexión a sus actualizaciones en vivo.
```json
{ "type": "open_flight", "flight_id": "AR1001", "ref": "r3" }
```

#### `close_flight`
Cancela la suscripción (el usuario salió del detalle).
```json
{ "type": "close_flight", "flight_id": "AR1001" }
```

#### `reserve_seat`
Inicia una reserva `pending` sobre un asiento. Arranca el timer de 1 minuto.
```json
{ "type": "reserve_seat", "flight_id": "AR1001", "seat_id": "12A", "ref": "r4" }
```

#### `pay`
Dispara el pago simulado (1-5 s en el backend). Si al terminar la reserva sigue `pending`,
se confirma.
```json
{ "type": "pay", "reservation_id": "res_abc", "ref": "r5" }
```

#### `cancel`
Cancela una reserva que siga `pending`.
```json
{ "type": "cancel", "reservation_id": "res_abc", "ref": "r6" }
```

#### `my_reservations`
Pide todas las reservas del usuario, en todos sus estados.
```json
{ "type": "my_reservations", "ref": "r7" }
```

---

### Servidor → Cliente

#### `registered`
Respuesta a `register`.
```json
{ "type": "registered", "user_id": "user_01", "name": "Ana", "ref": "r1" }
```

#### `flights`
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

#### `flight_detail`
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

#### `reservation_started`
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

#### `reservation_update`
Cambio de estado de **una reserva propia** (resultado de `pay`/`cancel`/expiración).
```json
{ "type": "reservation_update", "reservation_id": "res_abc", "status": "confirmed" }
```
`status` puede ser `"confirmed"`, `"cancelled"` o `"expired"`. (Cuando es respuesta directa
a un `pay`/`cancel`, lleva el `ref` correspondiente; cuando es por expiración, no lleva `ref`.)

#### `seat_update` (broadcast)
**Empujado a todas las conexiones suscriptas al vuelo** cuando cambia un asiento. Es lo que
mantiene sincronizados a varios clientes mirando el mismo vuelo.
```json
{ "type": "seat_update", "flight_id": "AR1001", "seat_id": "12A", "status": "confirmed" }
```

#### `my_reservations`
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

#### `error`
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

### Ejemplos de flujo

#### A) Reserva exitosa
```
→ register {name:"Ana"}                 ← registered {user_id}
→ list_flights {sort:"price_asc"}        ← flights [...]
→ open_flight {flight_id:"AR1001"}       ← flight_detail {seats:[...]}
→ reserve_seat {seat_id:"12A"}           ← reservation_started {reservation_id, expires_at}
                                         ⇐ seat_update {12A:"reserved"}  (a todos los suscriptos)
→ pay {reservation_id}                   ← reservation_update {confirmed}   (tras 1-5 s)
                                         ⇐ seat_update {12A:"confirmed"} (a todos)
```

#### B) Dos usuarios, mismo asiento (concurrencia)
```
Ana  → reserve_seat 12A   ← reservation_started   (ganó)
Beto → reserve_seat 12A   ← error {reason:"seat_taken"}   (perdió)
```

#### C) Expiración durante el pago (edge case)
```
→ reserve_seat 12A    ← reservation_started {expires_at}
   (pasan 60 s sin pagar)
                      ← reservation_update {expired}   (empujado, sin ref)
                      ⇐ seat_update {12A:"free"}
→ pay {reservation_id} ← error {reason:"not_pending"}   (el pago llegó tarde)
```


## Decisiones de diseño

> Registro de las decisiones de arquitectura tomadas en la Etapa 1, con su **porqué** y
> **cómo se defienden** en el coloquio. Al final, los **defaults menores a confirmar con
> el grupo**. Sirve de guía para la defensa oral y para que el grupo ratifique o cambie.

### Decisiones tomadas (firmes)

#### D1 — Pago simulado en el backend con `Task.Supervisor`
**Decisión:** el pago (demora aleatoria de 1-5 s) corre como una **tarea supervisada** del
lado del servidor. Flujo: el cliente manda `pay` → el `FlightServer` lanza, vía
`PaymentSupervisor` (`Task.Supervisor`), una tarea que espera 1-5 s y al terminar le manda
`confirm` al propio `FlightServer`. La confirmación se aplica **solo si la reserva sigue
`pending`**.

**Por qué:**
- El backend es la **única fuente de verdad**: la confirmación se decide en el servidor, no
  en el navegador.
- La demora **no debe correr dentro del `FlightServer`** (mientras duerme no atendería su
  mailbox y bloquearía el vuelo). Sacarla a una tarea mantiene al dueño del estado siempre
  receptivo (regla de la cátedra: "el dueño del estado decide rápido y delega el trabajo
  pesado").
- Cumple el requisito OTP del enunciado de tener **tareas auxiliares** separadas del dominio.
- Hace **natural** la carrera "pago vs. expiración" (edge case 8.2): el `confirm` que llega
  tarde se evalúa sobre el estado ya final y se ignora.

**Cómo se defiende:** "El pago es trabajo diferido; lo modelamos como una `Task` supervisada
para no bloquear el `FlightServer`. El resultado vuelve como un mensaje más, que el vuelo
serializa con las demás operaciones; por eso un pago tardío nunca pisa una expiración."

**Alternativa descartada:** simular la demora en el frontend. Más simple, pero deja la
lógica de pago como detalle de UI y aprovecha menos OTP.

#### D2 — Reservas `pending` al reiniciar → se re-arma su timer por `expires_at - now`
**Decisión (actualizada en Etapa 4 · restore):** al reconstruir un vuelo desde DETS, cada
reserva `:pending` persistida se evalúa contra su `expires_at`:
- si todavía le queda tiempo (`expires_at - now > 0`) → vuelve `:pending`, el asiento queda
  `:reserved` y se **re-arma** el timer por el tiempo restante;
- si ya venció → se cierra como `:expired` y libera el asiento (se corrige en disco).

Las `:confirmed` se recargan ocupando el asiento; las `:cancelled`/`:expired` quedan en el
historial sin tocar asientos.

**Por qué este refinamiento** (antes: "expirar todas las `pending` al bootear"):
- Desde la Etapa 3, `expires_at = now + ttl` es un **deadline confiable y persistido** (única
  fuente de verdad, ver D5 y `Reservation`). Con ese dato, re-armar por el tiempo restante es
  fiel al enunciado (la reserva conserva el minuto real que le quedaba) y no "regala" tiempo.
- El timer en memoria se pierde al reiniciar, pero **no hace falta inventarlo**: se recalcula
  desde `expires_at`. Una `pending` cuyo plazo ya pasó se cierra como `:expired` (no queda
  asiento retenido).

**Clave de la reconstrucción:** el estado de cada asiento lo define **solo su reserva
activa**. Sobre el esqueleto (asientos `:free`) se aplican únicamente las `:confirmed` y las
`:pending` vigentes; las finalizadas van al historial y **no** tocan el asiento. Como el
dominio garantiza una sola reserva activa por asiento, el resultado es **independiente del
orden de iteración** (si dejáramos a una `:expired` poner el asiento en `:free`, un asiento
expirado-y-luego-reconfirmado podría quedar libre según el orden de procesamiento).

**Cómo se defiende:** "Persistimos cada reserva con su `expires_at`. Al reconstruir, las
vigentes re-arman su timer por el tiempo restante y las vencidas se cierran como expiradas.
El asiento lo fija solo la reserva activa, así la reconstrucción es determinista."

#### D3 — WebSocket con `cowboy` puro + `jason`
**Decisión:** usar la dependencia **`cowboy`** directamente, con un handler
`:cowboy_websocket`, y **`jason`** para (de)serializar JSON. Son las **únicas** dependencias
extra del backend.

**Por qué:**
- El TP es esencialmente WebSocket; `cowboy` puro nos da exactamente eso con **mínima
  superficie** y control total, sin capas intermedias que explicar.
- `jason` es la librería JSON estándar del ecosistema; es necesaria sí o sí para hablar con
  el navegador.
- Mantener **pocas dependencias** facilita la defensa oral (entendemos todo lo que corre).

**Cómo se defiende:** "Elegimos `cowboy` puro en vez de `plug_cowboy` porque solo
necesitamos un endpoint WebSocket; no queríamos sumar `Plug` como capa extra. `jason` es la
librería JSON de facto. Nada más."

**Alternativa descartada:** `plug_cowboy` (cómodo si hubiera muchos endpoints HTTP, pero
agrega `Plug` para defender).

#### D4 — Supervisor raíz con estrategia `:rest_for_one`
**Decisión:** el supervisor raíz usa `:rest_for_one` con los hijos ordenados por
dependencia: `Persistence` → `Registry` → `FlightSupervisor` → `PaymentSupervisor` →
`WebEndpoint` (en el código final no hay `UserServer` ni `Catalog` separados — ver
docs/arquitectura.md §3.7 — pero el criterio de orden por dependencia es el mismo).

**Por qué:**
- Hay una **cadena de dependencias**: los `FlightServer` se registran en `Registry` y
  cargan de `Persistence`. Si `Registry` cae, los `FlightServer` quedan "vivos pero no
  encontrables". Con `:rest_for_one`, al reiniciar `Registry` se reinician también los que
  arrancaron **después** (incluido `FlightSupervisor`), que se re-registran y recargan
  desde DETS → todo vuelve consistente.
- `WebEndpoint` arranca último: solo aceptamos conexiones con el dominio ya listo.

**Cómo se defiende:** "Ordenamos los hijos por dependencia y usamos `:rest_for_one` para que
una caída en una pieza base reinicie a los que dependen de ella, sin tocar a los anteriores.
Así nunca quedan procesos colgados de un `Registry` que ya no existe."

**Alternativa descartada:** `:one_for_one` (más simple, pero dejaría los `FlightServer`
inconsistentes ante una caída de `Registry`/`Persistence`).

#### D5 — Ids de reserva generados por el `FlightServer` (contador legible)
**Decisión:** el `FlightServer` (la cáscara con efectos sobre `Booking.Flight`) genera los
ids de reserva con un **contador por vuelo**: `"<flight_id>-r<n>"` (ej. `"AR1001-r1"`).
Son únicos entre vuelos porque el `flight_id` lo es, y legibles para la demo y el coloquio.

**Por qué:** generar un id es un efecto (no determinista) → vive en el proceso, no en el
dominio puro. Un contador en el estado del GenServer es simple y se serializa solo (el
proceso atiende los pedidos de a uno).

**Deuda a saldar en la etapa de persistencia:** el contador (`seq`) vive en memoria. Al
reiniciar el servidor y recargar las reservas desde DETS hay que **restaurar
`seq = max(n existente) + 1`** (el mayor sufijo numérico entre las reservas ya
persistidas, más uno) para que los ids nuevos **no colisionen** con los ya emitidos.
Mientras no haya persistencia, `seq` arranca en 1.

**Alternativa:** id aleatorio (`System.unique_integer`) — sin esa deuda, pero menos legible.

#### D6 — Persistencia: un único `Persistence` dueño de DETS, write-through sincrónico
**Decisión:** un solo proceso `Booking.Persistence` (GenServer) es dueño de las tablas DETS
(`users`, `flights`, `reservations`); todos leen y escriben **a través de él**. Cada cambio
de reserva en un `FlightServer` se persiste de forma **sincrónica** (write-through: se
guarda **antes** de responderle al cliente).

**Por qué un único dueño:**
- DETS no soporta escritura concurrente sin coordinación: varios procesos sobre el mismo
  archivo pueden **corromperlo**. Con un solo dueño, **todas las escrituras se serializan**
  ahí → consistencia, sin locks. Es el mismo trade-off "single owner" del resumen.
- A la escala del TP el costo de serializar es **despreciable** (escrituras DETS rápidas,
  volumen bajo). Si alguna vez hubiera que escalar, se **particiona** (p. ej. una partición
  por aerolínea o por rango de vuelos); no se rompe el invariante.

**Por qué sincrónico:** se persiste antes de responder, así al usuario se le confirma una
operación recién cuando ya quedó en disco (sostiene "tras reiniciar no se pierden reservas").

**Cómo se defiende:** "Un proceso dueño de DETS evita la corrupción y serializa la E/S; el
write-through sincrónico da durabilidad antes de confirmarle al cliente. El costo es mínimo
a esta escala y, de hacer falta, se particiona."

#### D7 — Pago simulado: Task supervisada que avisa, el FlightServer decide
**Decisión:** `pay` lanza una `Task` bajo `Booking.PaymentSupervisor` (`Task.Supervisor`) que
duerme 1-5 s y le **manda el resultado** al `FlightServer` (`{:payment_result, id, result}`).
La Task **no confirma sola**: el `FlightServer` confirma **solo si la reserva sigue
`:pending`** (re-validación con `Flight.confirm/2`). El timer de expiración **sigue corriendo**
durante el pago (no se cancela al iniciarlo).

**Por qué la Task (y no dormir dentro del FlightServer):** el `FlightServer` serializa todo el
vuelo; dormir 1-5 s en `handle_call` lo bloquearía y **congelaría el vuelo entero** (no
atendería otras reservas ni los timers de expiración). Delegar el trabajo lento a una Task lo
mantiene receptivo (regla del resumen: "el dueño del estado decide rápido y delega").

**Por qué el timer sigue corriendo:** así la carrera **pago-vs-expiración** la resuelve el
orden de llegada a la mailbox. Si expira primero, el pago tardío es no-op (la reserva ya no
está `:pending`); si paga primero, se confirma y se cancela el timer. Nunca quedan dos verdades.

**Tasa de éxito configurable** (`:payment_success_rate`, default **1.0** = siempre `:ok`) para
que la demo en vivo no dependa del azar; el rechazo se fuerza bajando el knob (o con
`force: :error` en tests). **Doble-pay:** se registra la reserva "en pago" (`payments`) para no
lanzar dos Tasks a la vez.

**Cómo se defiende:** "El pago es trabajo lento: corre en una Task supervisada para no bloquear
el vuelo. La Task solo avisa el resultado; confirmar es decisión del `FlightServer`, que
re-valida que la reserva siga pendiente. Como el timer no se cancela, la carrera con la
expiración se resuelve sola y de forma consistente."

#### D8 — Búsqueda/orden: filtro server-side en `list_flights` + filtrado client-side en el front
**Decisión:** el backend implementa el filtro (por `date`, `destination`) y el orden (por
`price`, `price_asc`/`price_desc`) en `Booking.Protocol` antes de responder `list_flights`
(cumple enunciado 5.3). El **frontend**, además, mantiene su propio filtro/orden **client-side**
con `useMemo` sobre los vuelos ya traídos (patrón del resumen de la cátedra), para una UX
instantánea sin round-trips por cada tecla.

**Por qué ambos:** el server-side cubre el requisito "buscar por fecha/destino" del enunciado y
queda testeado; el client-side da la experiencia fluida del listado. No se contradicen: el front
pide todo el catálogo una vez y filtra en memoria; el filtro del backend está disponible para
quien lo quiera usar por protocolo.

#### D9 — Broadcast: `reservation_update` a todos los suscriptos (el cliente filtra)
**Decisión:** el `FlightServer` manda `seat_update` (estado público del asiento) y
`reservation_update` (cambio de reserva) **a todos los suscriptos** del vuelo. El cliente
reacciona a `seat_update` siempre, y a `reservation_update` **solo si el `reservation_id` es
suyo** (lleva sus ids en memoria).

**Por qué:** evita trackear `user_id` en la suscripción (más simple) y da la misma UX. El único
costo es que un `reservation_id` ajeno "se ve" en el canal (sin datos del usuario); para el TP
es aceptable. Alternativa (no tomada): mandar `reservation_update` solo al dueño.

#### D10 — Frontend: React + Vite, WebSocket nativo, vistas por estado (sin router)
**Decisión:** frontend en **React (Vite), JavaScript**, con el **WebSocket nativo** del navegador
(sin librerías de cliente WS) y **CSS simple** propio. **Sin router**: las vistas se eligen por
estado (`search`/`detail`/`reservations`), porque el flujo es chico. La conexión + estado viven
en un hook (`useBooking`) con `useReducer`; los componentes son funcionales chicos.

**Por qué:** menos dependencias (solo React/Vite), más fácil de defender; el WS nativo alcanza
para el protocolo; las pantallas son pocas. El tiempo real se maneja en el reducer: `seat_update`
actualiza la grilla, `reservation_update` actualiza la reserva activa y "mis reservas".

---

### Defaults menores — **A CONFIRMAR CON EL GRUPO**

> No bloquean la arquitectura; son elecciones razonables que tomé para avanzar, pero el
> grupo debería ratificarlas o cambiarlas.

#### C1 — Namespace OTP `Booking`
Todos los módulos cuelgan de `Booking.*` (`Booking.FlightServer`, etc.). Es solo un nombre;
si el grupo prefiere otro (`Flights`, `Reservas`, el nombre del proyecto del grupo, etc.),
es un cambio mecánico. **A confirmar.**

#### C2 — Usuario solo por nombre, sin password
El `register` toma solo un `name` y devuelve un `user_id`. No hay autenticación real
(login/clave). Para un TP centrado en concurrencia y tiempo real alcanza, pero **a
confirmar** si el grupo quiere algo más (p. ej. email, o evitar nombres duplicados).

#### C3 — Estado de los asientos **derivado** de las reservas (sin tabla `seats`)
No persistimos una tabla de asientos aparte. El estado de cada asiento se **reconstruye**
al bootear a partir de las reservas del vuelo: una reserva `:confirmed` ⇒ asiento ocupado;
sin reserva activa ⇒ asiento libre.

**El enunciado pide "persistir el estado actual de los asientos". ¿Por qué el estado
derivado igual lo cumple?**
- El requisito real es de **comportamiento**: tras apagar y levantar, el estado de los
  asientos debe quedar correcto. Eso se cumple: reconstruimos los asientos desde las
  reservas persistidas y quedan exactamente como correspondía.
- Las reservas (que **sí** persistimos) **determinan unívocamente** el estado de los
  asientos. Guardar los asientos por separado sería **información redundante** y abre la
  puerta a que asientos y reservas se contradigan (dos fuentes de verdad). Derivar mantiene
  **una sola fuente de verdad**, que es más correcto y más fácil de defender.
- Combina con D2 (más arriba): como las
  `pending` se expiran al bootear, al reconstruir solo las `:confirmed` ocupan asiento.

**A confirmar:** si en el coloquio se prefiere mostrar una tabla `seats` explícita, es un
cambio acotado (agregar la tabla y escribir el estado del asiento en cada transición). Lo
dejamos anotado como opción.

