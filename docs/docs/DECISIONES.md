# Decisiones de diseño

> Registro de las decisiones de arquitectura tomadas en la Etapa 1, con su **porqué** y
> **cómo se defienden** en el coloquio. Al final, los **defaults menores a confirmar con
> el grupo**. Sirve de guía para la defensa oral y para que el grupo ratifique o cambie.

## Decisiones tomadas (firmes)

### D1 — Pago simulado en el backend con `Task.Supervisor`
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

### D2 — Reservas `pending` al reiniciar → se re-arma su timer por `expires_at - now`
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

### D3 — WebSocket con `cowboy` puro + `jason`
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

### D4 — Supervisor raíz con estrategia `:rest_for_one`
**Decisión:** el supervisor raíz usa `:rest_for_one` con los hijos ordenados por
dependencia: `Persistence` → `Registry` → `UserServer` → `Catalog` → `FlightSupervisor` →
`PaymentSupervisor` → `WebEndpoint`.

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

### D5 — Ids de reserva generados por el `FlightServer` (contador legible)
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

### D6 — Persistencia: un único `Persistence` dueño de DETS, write-through sincrónico
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

### D7 — Pago simulado: Task supervisada que avisa, el FlightServer decide
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

### D8 — Búsqueda/orden: filtro server-side en `list_flights` + filtrado client-side en el front
**Decisión:** el backend implementa el filtro (por `date`, `destination`) y el orden (por
`price`, `price_asc`/`price_desc`) en `Booking.Protocol` antes de responder `list_flights`
(cumple enunciado 5.3). El **frontend**, además, mantiene su propio filtro/orden **client-side**
con `useMemo` sobre los vuelos ya traídos (patrón del resumen de la cátedra), para una UX
instantánea sin round-trips por cada tecla.

**Por qué ambos:** el server-side cubre el requisito "buscar por fecha/destino" del enunciado y
queda testeado; el client-side da la experiencia fluida del listado. No se contradicen: el front
pide todo el catálogo una vez y filtra en memoria; el filtro del backend está disponible para
quien lo quiera usar por protocolo.

### D9 — Broadcast: `reservation_update` a todos los suscriptos (el cliente filtra)
**Decisión:** el `FlightServer` manda `seat_update` (estado público del asiento) y
`reservation_update` (cambio de reserva) **a todos los suscriptos** del vuelo. El cliente
reacciona a `seat_update` siempre, y a `reservation_update` **solo si el `reservation_id` es
suyo** (lleva sus ids en memoria).

**Por qué:** evita trackear `user_id` en la suscripción (más simple) y da la misma UX. El único
costo es que un `reservation_id` ajeno "se ve" en el canal (sin datos del usuario); para el TP
es aceptable. Alternativa (no tomada): mandar `reservation_update` solo al dueño.

### D10 — Frontend: React + Vite, WebSocket nativo, vistas por estado (sin router)
**Decisión:** frontend en **React (Vite), JavaScript**, con el **WebSocket nativo** del navegador
(sin librerías de cliente WS) y **CSS simple** propio. **Sin router**: las vistas se eligen por
estado (`search`/`detail`/`reservations`), porque el flujo es chico. La conexión + estado viven
en un hook (`useBooking`) con `useReducer`; los componentes son funcionales chicos.

**Por qué:** menos dependencias (solo React/Vite), más fácil de defender; el WS nativo alcanza
para el protocolo; las pantallas son pocas. El tiempo real se maneja en el reducer: `seat_update`
actualiza la grilla, `reservation_update` actualiza la reserva activa y "mis reservas".

---

## Defaults menores — **A CONFIRMAR CON EL GRUPO**

> No bloquean la arquitectura; son elecciones razonables que tomé para avanzar, pero el
> grupo debería ratificarlas o cambiarlas.

### C1 — Namespace OTP `Booking`
Todos los módulos cuelgan de `Booking.*` (`Booking.FlightServer`, etc.). Es solo un nombre;
si el grupo prefiere otro (`Flights`, `Reservas`, el nombre del proyecto del grupo, etc.),
es un cambio mecánico. **A confirmar.**

### C2 — Usuario solo por nombre, sin password
El `register` toma solo un `name` y devuelve un `user_id`. No hay autenticación real
(login/clave). Para un TP centrado en concurrencia y tiempo real alcanza, pero **a
confirmar** si el grupo quiere algo más (p. ej. email, o evitar nombres duplicados).

### C3 — Estado de los asientos **derivado** de las reservas (sin tabla `seats`)
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
- Combina con [D2](#d2--reservas-pending-al-reiniciar--se-expiran-al-bootear): como las
  `pending` se expiran al bootear, al reconstruir solo las `:confirmed` ocupan asiento.

**A confirmar:** si en el coloquio se prefiere mostrar una tabla `seats` explícita, es un
cambio acotado (agregar la tabla y escribir el estado del asiento en cada transición). Lo
dejamos anotado como opción.
