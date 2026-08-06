# Arquitectura — Sistema de reserva de asientos

> Documento de contrato para revisión del grupo (Etapa 1). Describe la arquitectura de
> procesos del backend (Elixir/OTP) y la relación cliente-servidor. Pensado para ser
> **defendible oralmente** en el coloquio: cada pieza tiene un *por qué*.

## 1. Visión cliente-servidor

```
   NAVEGADOR (React + Vite)                       BACKEND (Elixir / OTP)
 ┌───────────────────────────┐                ┌──────────────────────────────┐
 │  UI: listado, detalle de   │   WebSocket    │  WebEndpoint (Cowboy)         │
 │  vuelo, asientos, pago,    │  <==========>  │  1 proceso por conexión       │
 │  "mis reservas"            │   JSON         │  (traduce JSON <-> dominio)   │
 └───────────────────────────┘                │            │                  │
                                               │            v                  │
                                               │  Dominio: FlightServer        │
                                               │  (un proceso por vuelo)       │
                                               │            │                  │
                                               │            v                  │
                                               │  Persistence (DETS)           │
                                               │  (vuelos, usuarios, reservas) │
                                               └──────────────────────────────┘
```

- El **frontend nunca decide el estado**: solo muestra lo que el backend le manda y le
  pide operaciones. La fuente de verdad es siempre el backend.
- La comunicación es por **WebSocket** (full-duplex): el cliente manda pedidos y el
  servidor puede **empujar** cambios en tiempo real (un asiento que otro usuario reservó).
- El protocolo concreto de mensajes y las entidades del dominio están en
  [documentacion-tecnica.md](documentacion-tecnica.md).

## 2. Árbol de supervisión

```
Booking.Application                       (punto de entrada OTP)
└── Booking.Supervisor                    (supervisor raíz, strategy: :rest_for_one)
    ├── Booking.Persistence               (GenServer: dueño de las tablas DETS)
    ├── Booking.Registry                  (Registry: {:flight, id} -> pid del FlightServer)
    ├── Booking.FlightSupervisor          (DynamicSupervisor: 1 FlightServer por vuelo)
    │   ├── Booking.FlightServer (vuelo AR1001)
    │   ├── Booking.FlightServer (vuelo AR1002)
    │   └── ...                            (uno por vuelo activo)
    ├── Booking.PaymentSupervisor         (Task.Supervisor: pagos simulados 1-5 s)
    └── Booking.WebEndpoint               (listener Cowboy/WebSocket)
        └── (Cowboy/Ranch supervisa 1 proceso por cada conexión WebSocket)
```

El árbol se arma **de arriba hacia abajo**: la `Application` arranca el supervisor raíz, y
ese supervisor arranca a sus hijos en el orden listado (el orden importa, ver §4).

### Separación de responsabilidades (lo que pide el enunciado: conexión / dominio / auxiliares)

| Capa | Procesos | Rol |
|------|----------|-----|
| **Conexión** | `WebEndpoint` + 1 proceso por conexión (Cowboy/Ranch) | Hablan WebSocket/JSON con el navegador. No tienen lógica de dominio: traducen mensajes y reenvían. |
| **Dominio** | `FlightServer` (uno por vuelo) | Dueño del estado dinámico de ese vuelo (asientos, reservas, timers, suscriptores) y de sus reglas, vía `Booking.Flight` (dominio puro). Única fuente de verdad de ese vuelo. |
| **Auxiliares** | `PaymentSupervisor` (tareas de pago), timers de expiración | Trabajo puntual o diferido que no debe bloquear al dueño del estado. |
| **Infraestructura** | `Supervisor`, `FlightSupervisor`, `Registry`, `Persistence` | Organización, ruteo, tolerancia a fallos y persistencia. El catálogo de vuelos y los usuarios registrados se leen/escriben directo contra `Persistence` desde `Booking.Protocol`, sin un proceso propio: son consultas de baja contención que no necesitan más serialización que la que ya da `Persistence` (ver §3.7). |

## 3. Por qué cada pieza (defensa oral)

### 3.1. Un `FlightServer` (GenServer) por vuelo — el corazón del diseño
Cada vuelo tiene **su propio proceso**, dueño exclusivo del estado de ese vuelo: sus
asientos, las reservas sobre él, sus timers y la lista de clientes que lo están mirando.

- **Por qué uno por vuelo y no uno global:** un único proceso global para todo el sistema
  sería un cuello de botella (atiende un mensaje por vez) y un único punto de falla. Con
  un proceso por vuelo, dos vuelos distintos se operan **en paralelo real**; la
  serialización solo ocurre donde hace falta: dentro de un mismo vuelo.
- **Cómo resuelve la concurrencia (clave del TP):** si dos usuarios intentan reservar el
  asiento 12A del vuelo AR1001 "al mismo tiempo", mandan dos mensajes al **mismo**
  `FlightServer`. El GenServer los atiende **de a uno** desde su mailbox: el primero deja
  el asiento `:reserved`, el segundo se evalúa sobre el estado ya actualizado y recibe
  `{:error, :seat_taken}`. **No hacen falta locks**: el proceso es un serializador natural
  (mismo principio de "estado aislado + paso de mensajes": nadie comparte memoria, todo
  pasa por mensajes a la mailbox).
- Es la **unidad de consistencia** del sistema: todo lo crítico de un vuelo pasa por acá.

### 3.2. `DynamicSupervisor` para los vuelos
Los vuelos **no se conocen como hijos fijos** en tiempo de compilación (se cargan de
DETS / se siembran al arrancar, y conceptualmente podrían agregarse en runtime). Un
`Supervisor` clásico tiene una lista fija de hijos; un **`DynamicSupervisor`** permite
arrancar hijos **bajo demanda**: al bootear iteramos los vuelos persistidos y levantamos
un `FlightServer` por cada uno. Si un `FlightServer` crashea, el `DynamicSupervisor` lo
reinicia y vuelve a cargar su estado desde DETS.

> *(No visto en clase — a defender en detalle.)* La diferencia con `Supervisor` es
> exactamente esa: hijos dinámicos vs. lista estática.

### 3.3. `Registry` para direccionar vuelos
Necesitamos mandarle un mensaje "al `FlightServer` del vuelo AR1001" sin guardar PIDs a
mano. El **`Registry`** mapea una clave lógica `{:flight, "AR1001"}` al PID del proceso.
El `FlightServer` se registra al arrancar usando `{:via, Registry, {Booking.Registry,
{:flight, id}}}`, y cualquiera resuelve el PID por la clave. Si el proceso crashea y el
supervisor lo recrea, se re-registra solo.

> *(No visto en clase — a defender en detalle.)* `Registry` es un proceso que mantiene un
> índice clave→PID, con limpieza automática cuando un proceso registrado muere.

### 3.4. Broadcast en tiempo real por *monitors* (sin Phoenix.PubSub)
Cuando un cliente abre un vuelo, su proceso de conexión se **suscribe** al `FlightServer`
de ese vuelo. El `FlightServer` guarda en su estado un `MapSet` de los PIDs suscriptos y
**los monitorea** (`Process.monitor/1`). Ante cualquier cambio (reserva, confirmación,
cancelación, expiración) recorre ese set y empuja un `seat_update` a cada conexión, que lo
reenvía al navegador.

- **Por qué monitors:** si un cliente se desconecta con una reserva pendiente (edge case
  del enunciado), el `FlightServer` recibe un mensaje `:DOWN` y **saca solo** ese PID de
  los suscriptos, sin ensuciar el estado ni intentar empujarle mensajes a un proceso
  muerto.
- **Por qué no Phoenix.PubSub:** sería una dependencia y una capa extra para defender. Con
  un `MapSet` + monitors cubrimos el requisito de tiempo real con piezas que ya tenemos y
  que entendemos al 100%.

### 3.5. Expiración con `Process.send_after` (dentro del `FlightServer`)
Al crear una reserva `pending`, el `FlightServer` programa
`Process.send_after(self(), {:expire, reservation_id}, 60_000)` y guarda el `timer_ref`.

- **Por qué dentro del proceso dueño:** la expiración es una operación crítica más sobre el
  vuelo, así que debe **serializarse** con las demás. Al disparar, llega como `handle_info`
  y se atiende en la misma cola que `reserve`/`confirm`/`cancel`. Esto resuelve la carrera
  "confirmar vs. expirar" (edge case 8.2): el proceso atiende uno primero; el segundo se
  evalúa sobre el estado ya final y no rompe la invariante de "un único estado final".
- Si la reserva se confirma o cancela antes, se hace `Process.cancel_timer(timer_ref)` para
  no recibir una expiración fantasma (y aunque llegara, se ignora porque la reserva ya no
  está `pending`).

### 3.6. `Persistence` — único dueño de DETS
Un GenServer es el **único** que toca las tablas DETS (`users`, `flights`,
`reservations`). Todos escriben/leen a través de él (write-through: cada transición de
reserva se persiste).

- **Por qué un solo dueño:** DETS no está pensado para acceso concurrente desde varios
  procesos; centralizar el acceso en un proceso evita corrupción y serializa la E/S.
- Al bootear, los `FlightServer` piden a `Persistence` el vuelo y sus reservas para
  reconstruir su estado en memoria (ver [documentacion-tecnica.md](documentacion-tecnica.md)).

> *(DETS no visto en clase — a defender.)* DETS = *Disk-based ETS*: tablas clave-valor
> persistidas en archivo, propiedad de un proceso.

### 3.7. Catálogo y usuarios: sin proceso propio
Esta sección documentaba originalmente un `Catalog` y un `UserServer` como `GenServer`
separados. En el código final **no existen**: el catálogo de vuelos y los usuarios
registrados se resuelven directo contra `Booking.Persistence`, sin proceso intermedio.

- **Catálogo (aerolíneas / aeropuertos / vuelos):** aerolíneas y aeropuertos son datos
  **estáticos**, embebidos como listas fijas en `Booking.Seed` (no hay nada que mutar, así
  que no hace falta proceso). Los vuelos sembrados sí se persisten (tabla `flights`);
  `list_flights` los lee con `Persistence.get_flights/1` y filtra/ordena con funciones
  puras de `Booking.Protocol` (`filter_by_date/2`, `filter_by_destination/2`,
  `sort_flights/2`) — son lecturas baratas que no necesitan tocar ningún `FlightServer`.
- **Usuarios:** `Booking.Protocol.find_or_create_user/2` busca por nombre con
  `Persistence.get_users/1` y, si no existe, lo crea con `Persistence.put_user/2`
  (write-through). Es baja contención (registrarse es poco frecuente), así que no hace
  falta un proceso propio: `Persistence` ya serializa esa escritura como cualquier otra.

**Por qué se simplificó así:** ambos son casos de baja contención y consultas simples;
sumar un `GenServer` por cada uno sería una capa de indirección sin beneficio real de
consistencia (`Persistence` ya serializa la E/S) — coherente con la regla de
"simplicidad antes que sofisticación" del proyecto.

### 3.8. `PaymentSupervisor` (`Task.Supervisor`) — pago simulado
El pago simulado tarda 1-5 s. Ese tiempo **no debe bloquear** al `FlightServer` (mientras
duerme no atendería su mailbox). Por eso el pago corre como una **tarea supervisada**:
`pay` → el `FlightServer` marca la reserva, pide a `PaymentSupervisor` una tarea que espera
1-5 s y, al terminar, manda `confirm` de vuelta al `FlightServer`. La confirmación se
aplica **solo si la reserva sigue `pending`** (un pago que llega tarde no confirma).

> *(Task.Supervisor no visto en clase — a defender.)* Es un supervisor especializado en
> tareas efímeras; si una tarea falla, no tumba al resto.

### 3.9. `WebEndpoint` (Cowboy) y procesos de conexión
Cowboy levanta un listener WebSocket. Por **cada conexión** del navegador, Cowboy/Ranch
crea **un proceso** (lo supervisa la propia infraestructura de Cowboy, no nuestro árbol).
Ese proceso de conexión: decodifica el JSON entrante, llama al dominio, se suscribe a
vuelos, y cuando un `FlightServer` le empuja un cambio (`handle_info`) lo serializa a JSON
y lo manda al navegador.

> *(Cowboy no visto en clase — a defender.)* Usamos `cowboy` puro con un handler
> `:cowboy_websocket` (ver [documentacion-tecnica.md](documentacion-tecnica.md), D3).

## 4. Estrategia del supervisor raíz: `:rest_for_one`

Los hijos están **ordenados por dependencia**: `Persistence` → `Registry` →
`FlightSupervisor` → `PaymentSupervisor` → `WebEndpoint`. Con `:rest_for_one`, si un hijo
cae, se reinician **él y los que arrancaron después** (los que dependen de él), pero no
los anteriores.

- **Por qué importa el orden:** los `FlightServer` se registran en `Registry`. Si `Registry`
  crasheara, los `FlightServer` quedarían "vivos pero no encontrables". Con `:rest_for_one`,
  al reiniciarse `Registry` también se reinicia `FlightSupervisor` (y sus
  `FlightServer`), que se vuelven a registrar y recargan su estado desde DETS. Queda todo
  consistente.
- `WebEndpoint` arranca **último**: recién aceptamos conexiones cuando el dominio está listo.
- Alternativa más simple (`:one_for_one`, cada hijo aislado) quedó descartada porque dejaría
  los `FlightServer` inconsistentes ante una caída de `Registry`/`Persistence`.

## 5. Flujo de una reserva (camino feliz)

```
Cliente            Conexión(Cowboy)        FlightServer(AR1001)        PaymentSupervisor
  │  reserve_seat 12A   │                        │                          │
  │ ──────────────────> │ ── reserve(12A) ─────> │  asiento -> :reserved     │
  │                     │                        │  crea reserva :pending    │
  │                     │                        │  send_after 60s (expira)  │
  │ <─ reservation_started (expires_at)          │                          │
  │ <═ seat_update 12A=:reserved  (a TODOS los suscriptos del vuelo)         │
  │                     │                        │                          │
  │  pay                │                        │                          │
  │ ──────────────────> │ ── pay ──────────────> │ ── start_child (1-5s) ──> │  (duerme)
  │                     │                        │ <──────── confirm ─────── │
  │                     │                        │  si sigue :pending:        │
  │                     │                        │  reserva -> :confirmed     │
  │                     │                        │  asiento -> :confirmed     │
  │                     │                        │  cancel_timer              │
  │ <─ reservation_update :confirmed             │                          │
  │ <═ seat_update 12A=:confirmed (a todos)      │                          │
```

Casos de conflicto (dos usuarios mismo asiento, confirmar tras expirar, cancelar tras
confirmar) se resuelven porque **todo pasa por el mismo `FlightServer`** que atiende un
mensaje por vez; ver invariantes en [documentacion-tecnica.md](documentacion-tecnica.md).

## 6. Resumen de "qué defender" en el coloquio

1. **Concurrencia por diseño:** un proceso por vuelo serializa lo crítico; no usamos locks.
2. **DynamicSupervisor + Registry:** vuelos como hijos dinámicos, direccionables por id.
3. **Tiempo real:** suscriptores en el `FlightServer` + monitors para limpiar desconexiones.
4. **Expiración:** timer dentro del proceso dueño, serializado con el resto, cancelable.
5. **Tolerancia a fallos:** `:rest_for_one` ordenado por dependencia; recarga desde DETS.
6. **Persistencia:** un único dueño de DETS; el estado de asientos se deriva de las reservas.
7. **Separación conexión / dominio / auxiliares**, tal como pide el enunciado.
