# Modelo de datos

> Entidades del dominio, sus campos, sus estados y dónde viven / se persisten. Identificadores
> en inglés; el modelo se mantiene chico y con **una sola fuente de verdad** por dato.

## Resumen de dónde vive cada cosa

| Entidad | Estática/Dinámica | Proceso dueño en memoria | ¿Se persiste en DETS? |
|---------|-------------------|--------------------------|------------------------|
| `Airline` | estática | `Catalog` (catálogo fijo) | embebida con los vuelos / catálogo fijo |
| `Airport` | estática | `Catalog` (catálogo fijo) | catálogo fijo |
| `Flight` | estática | `Catalog` | sí (tabla `flights`) |
| `Seat` | dinámica | `FlightServer` del vuelo | **derivado** (no tiene tabla propia, ver abajo) |
| `Reservation` | dinámica | `FlightServer` del vuelo | sí (tabla `reservations`) |
| `User` | dinámica | `UserServer` | sí (tabla `users`) |

## Entidades

### `User`
Usuario registrado del sistema.

| Campo | Tipo | Notas |
|-------|------|-------|
| `id` | string | identificador único (generado por el backend) |
| `name` | string | nombre con el que se registró |

> **A confirmar con el grupo:** por ahora el registro es **solo por nombre, sin password**
> (ver [DECISIONES.md](DECISIONES.md)). Si más adelante se quiere, se agrega `email`/clave.

### `Airline`
Aerolínea ficticia. El enunciado pide **5 aerolíneas**.

| Campo | Tipo | Notas |
|-------|------|-------|
| `id` | string | ej. `"condor"` |
| `name` | string | ej. `"Cóndor del Sur"` |

### `Airport`
Aeropuerto nacional argentino (origen/destino de los vuelos).

| Campo | Tipo | Notas |
|-------|------|-------|
| `code` | string | ej. `"EZE"`, `"AEP"`, `"COR"`, `"BRC"` |
| `city` | string | ej. `"Buenos Aires"`, `"Córdoba"`, `"Bariloche"` |

### `Flight`
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

### `Seat`
Asiento de un vuelo. Vive dentro del `FlightServer`. **No tiene tabla propia en DETS**: su
estado se **deriva** de las reservas al reconstruir el vuelo (ver [DECISIONES.md](DECISIONES.md)).

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

### `Reservation`
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

## Invariantes del dominio (deben cumplirse SIEMPRE)

1. Un asiento no puede estar asignado a dos usuarios a la vez.
2. Reserva `:confirmed` ⇒ asiento `:confirmed` (definitivo). Reserva `:cancelled`/`:expired`
   ⇒ asiento `:free`.
3. Una reserva termina en un **único estado final**: `:pending` → `:confirmed` |
   `:cancelled` | `:expired`.
4. No se puede confirmar una reserva ya expirada o cancelada.
5. Si dos usuarios reservan el mismo asiento a la vez, **solo uno** lo consigue
   (lo garantiza la serialización en el `FlightServer`).
6. Tras apagar y reiniciar el servidor, no se pierden usuarios, vuelos ni reservas
   persistidas; el estado de los asientos se reconstruye coherente (ver
   [DECISIONES.md](DECISIONES.md): las `:pending` pasan a `:expired` al bootear).

## Relación con la persistencia

- `users`, `flights` y `reservations` se guardan en DETS (tablas clave-valor).
- El **estado de los asientos no se guarda aparte**: queda determinado por las reservas
  (`:confirmed` ocupa el asiento; el resto lo deja libre). Al levantar un `FlightServer` se
  carga el `Flight` (para saber `seat_count`) y sus reservas, y se reconstruye el mapa de
  asientos. Justificación de por qué esto cumple "persistir el estado de asientos" del
  enunciado: en [DECISIONES.md](DECISIONES.md).
