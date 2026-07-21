# Trabajo Práctico Final – Taller de Programación I

**Cátedra:** Manuel Camejo  
**Tema:** Sistema de reserva de asientos en vuelos  
**Entrega:** grupal – grupos de 3 o 4 personas  

---

## 1. Introducción

Queremos construir una nueva plataforma confiable de reserva de viajes.

La plataforma debe concentrar vuelos de distintas aerolíneas y permitir que múltiples usuarios busquen vuelos, consulten disponibilidad y reserven asientos en tiempo real.

En este contexto, la concurrencia deja de ser un detalle técnico y pasa a ser el corazón del sistema:

- varios usuarios pueden estar mirando el mismo vuelo al mismo tiempo;
- varios pueden intentar reservar el mismo asiento;
- una reserva puede quedar pendiente, confirmarse, cancelarse o expirar;
- el estado visible en todos los clientes debe mantenerse consistente.

La idea de este trabajo práctico es construir una versión simplificada pero realista de ese sistema, usando **Elixir + OTP** en el backend y una aplicación web en el frontend.

No se busca hacer “una aerolínea completa”, sino una aplicación cliente-servidor donde se vea con claridad:

- modelado de dominio;
- procesos en Elixir;
- WebSockets y tiempo real;
- coordinación entre múltiples clientes;
- resolución correcta de situaciones concurrentes.

---

## 2. Objetivo

Desarrollar una aplicación cliente-servidor para reserva de asientos en vuelos.

El sistema debe estar dividido en dos partes:

- un backend en Elixir, usando OTP y WebSockets;
- un frontend web que permita interactuar con el sistema en tiempo real.

---

## 3. Datos mínimos del sistema

El sistema debe trabajar con vuelos dentro de Argentina.

Como mínimo, debe cumplir estas condiciones:

- usar aeropuertos nacionales argentinos como origen y destino de los vuelos;
- definir 5 aerolíneas ficticias;
- cargar al menos 10 vuelos por aerolínea;
- permitir buscar vuelos, como mínimo, por:
  - fecha;
  - destino.

Las aerolíneas pueden ser inventadas libremente por cada grupo, siempre que mantengan una identidad clara y consistente dentro del sistema.

---

## 4. Descripción general del sistema

El sistema debe permitir trabajar con vuelos de distintas aerolíneas, consultar disponibilidad y reservar asientos.

Cada vuelo tiene una cantidad limitada de asientos. Distintos usuarios pueden estar mirando el mismo vuelo al mismo tiempo, y también pueden intentar reservar los mismos asientos en momentos cercanos.

El sistema debe garantizar que el estado final sea consistente.

En particular, una reserva:

- se inicia como pendiente;
- puede confirmarse mediante un pago simulado;
- puede cancelarse por decisión del usuario mientras siga pendiente;
- expira automáticamente después de 1 minuto si no se confirma.

Cuando una reserva cambia, los clientes conectados que estén viendo ese vuelo deben enterarse en tiempo real.

---

## 5. Backend – funcionalidades mínimas obligatorias

El backend debe estar implementado 100% en Elixir y debe incluir, como mínimo:

### 5.1. Dominio y estado

- Soporte para múltiples aerolíneas.
- Soporte para múltiples vuelos.
- Estado de los vuelos y de sus asientos.
- Estado de las reservas.
- Estado de los usuarios registrados.
- Cada vuelo debe tener entre 20 y 100 asientos.

### 5.2. Persistencia obligatoria

El sistema debe persistir, como mínimo:

- los usuarios registrados;
- los vuelos cargados;
- el estado actual de los asientos;
- el estado de todas las reservas realizadas.

Esto implica que debe ser posible:

- apagar el servidor;
- volver a levantarlo;
- conservar correctamente la información ya existente.

En particular, al reiniciar el sistema deben seguir estando disponibles:

- los usuarios registrados;
- los vuelos cargados;
- las reservas ya realizadas;
- el estado correcto de los asientos asociado a esas reservas.

La forma de persistencia queda a criterio del grupo, siempre que el comportamiento final cumpla con este requisito.

### 5.3. Operaciones principales

- Listar vuelos disponibles.
- Buscar vuelos por:
  - fecha;
  - destino.
- Consultar detalle de un vuelo.
- Consultar estado de los asientos de un vuelo.
- Iniciar una reserva sobre un asiento específico.
- Confirmar una reserva mediante un pago simulado.
- Cancelar una reserva pendiente.
- Expirar automáticamente reservas pendientes luego de 1 minuto.

### 5.4. Comunicación en tiempo real

- Uso de WebSocket para la comunicación con el cliente.
- Envío de actualizaciones en tiempo real cuando cambie el estado de un vuelo o de sus asientos.

### 5.5. OTP

- Uso de GenServer.
- Uso de Supervisor, DynamicSupervisor y Registry.
- Árbol de supervisión claro.
- Separación razonable entre procesos de conexión, procesos de dominio y tareas auxiliares.

---

## 6. Frontend – funcionalidades mínimas obligatorias

El frontend debe estar implementado en React. Para el setup inicial, pueden usar Vite.

Como mínimo, la experiencia de usuario debe permitir este flujo:

### 6.1. Búsqueda y listado de vuelos

Un usuario debe poder:

- ver un listado de vuelos disponibles;
- buscar o filtrar vuelos por:
  - fecha;
  - destino;
- ordenar vuelos por precio.

### 6.2. Detalle de un vuelo

Desde el listado, un usuario debe poder entrar al detalle de un vuelo y:

- ver información básica del vuelo;
- ver sus asientos;
- distinguir visualmente qué asientos están disponibles, reservados o confirmados;
- elegir un asiento para iniciar una reserva.

### 6.3. Flujo de reserva en la UI

Una vez elegido un asiento, el usuario debe poder:

- iniciar la reserva;
- avanzar a un paso de pago simulado;
- esperar la confirmación del pago;
- ver el resultado final de la operación.

El pago simulado debe cumplir estas condiciones:

- forma parte explícita del flujo de la UI;
- tarda en confirmarse entre 1 y 5 segundos, elegidos al azar;
- mientras la reserva esté pendiente, el usuario tiene 1 minuto para completar el proceso antes de que expire.

Si la reserva expira, el usuario debe volver a comenzar el flujo.

### 6.4. Gestión de reservas del usuario

El frontend debe incluir una vista donde el usuario pueda ver el estado de todas sus reservas.

Como mínimo, esa vista debe permitir ver reservas en estados como:

- pendiente;
- confirmada;
- cancelada;
- expirada.

### 6.5. Tiempo real

El frontend debe:

- reflejar en la interfaz los cambios recibidos desde el backend por WebSocket;
- actualizar el estado visible del vuelo si otro usuario reserva, cancela o confirma un asiento;
- reflejar correctamente en la UI si una reserva expira mientras el usuario está navegando o intentando pagar.

No hace falta que el frontend sea visualmente complejo. Se prioriza claridad funcional por sobre diseño gráfico.

---

## 7. Reglas mínimas del sistema

El sistema debe garantizar que:

- un asiento no puede quedar asignado a dos usuarios al mismo tiempo;
- una reserva confirmada deja el asiento asignado de forma definitiva;
- una reserva cancelada libera el asiento;
- una reserva expirada libera el asiento;
- una reserva confirmada no puede volver a tratarse como pendiente;
- si dos usuarios intentan reservar el mismo asiento concurrentemente, solo uno debe conseguirlo;
- luego de reiniciar el servidor, el sistema no debe perder usuarios, vuelos ni reservas persistidas.

---

## 8. Edge cases y situaciones concurrentes que el sistema debe manejar correctamente

El corazón del TP está en que el sistema se comporte bien frente a concurrencia real y estados límite.

Como mínimo, el sistema debe contemplar y resolver correctamente casos como estos:

### 8.1. Competencia por el mismo asiento

- Dos usuarios intentando reservar el mismo asiento al mismo tiempo.
- Un usuario viendo un asiento como disponible, mientras otro lo reserva antes de que confirme la operación.

### 8.2. Transiciones de reserva en conflicto

El sistema debe manejar correctamente casos donde una misma reserva recibe acciones incompatibles en momentos muy cercanos.

Por ejemplo:

- confirmación de pago y expiración de la reserva;
- cancelación y confirmación sobre la misma reserva;
- intento de confirmar una reserva que ya expiró;
- intento de cancelar una reserva que ya fue confirmada.

En todos estos casos, el sistema debe garantizar que la reserva termine en un único estado final válido.

### 8.3. Estado sincronizado entre clientes

- Múltiples clientes conectados viendo el mismo vuelo y recibiendo actualizaciones en tiempo real.
- Un cliente trabajando con información vieja mientras el backend ya cambió el estado real del vuelo.

### 8.4. Casos límite del flujo

- Búsqueda sin resultados.
- Vuelo sin asientos disponibles.
- Intento de reservar un asiento inexistente.
- Intento de operar sobre un vuelo inexistente.
- Desconexión de un cliente mientras una reserva sigue pendiente.
- Expiración de una reserva mientras el usuario está en el flujo de pago.

No alcanza con que el sistema “ande” en el caso feliz. Debe comportarse de forma consistente frente a estos escenarios.

---

## 9. Features opcionales para puntos extra

- Historial de reservas por usuario.
- Distintas clases de asiento.
- Mapa visual de asientos más elaborado.
- Persistencia o restauración de estado.
- Reconexión de clientes con recuperación de contexto.
- Notificaciones más ricas del lado del frontend.
- Simulación más completa del flujo de pago.
- Sistema de conexiones entre vuelos, es decir, itinerarios con más de un tramo.

---

## 10. Criterios de evaluación sugeridos

- Correcto uso de OTP y diseño del árbol de supervisión.
- Correcta separación de responsabilidades entre backend y frontend.
- Funcionamiento correcto del flujo de vuelos, asientos y reservas.
- Resolución correcta de situaciones concurrentes y edge cases importantes.
- Persistencia correcta de usuarios, vuelos, asientos y reservas.
- Capacidad de apagar y volver a levantar el servidor sin perder el estado requerido.
- Uso adecuado de WebSockets para mantener sincronizados cliente y servidor.
- Código limpio, modular y razonablemente bien organizado.
- Documentación clara y suficiente para levantar y probar el sistema.
- Demo en vivo del proyecto funcionando.
- Repositorio privado en GitHub con el código del grupo.
- Preguntas orales sobre arquitectura, procesos, supervisores, protocolo de mensajes y decisiones de diseño.

---

## 11. Fecha de entrega

Las entregas y defensas del TP final se realizarán en alguno de estos días:

- 16 de julio
- 23 de julio
- 30 de julio

En todos los casos, el horario será de 16:00 a 19:00.

Fechas de recuperación:

- 6 de agosto
- 13 de agosto

---

## 12. Entrega

La entrega consiste en:

- Repositorio privado en GitHub con el código completo.
- `README.md` con:
  - cómo instalar dependencias;
  - cómo levantar el backend;
  - cómo levantar el frontend;
  - cómo correr el sistema;
  - cómo probarlo;
  - cómo reproducir una demo básica.
- Demo en vivo durante la clase de entrega.
- Opcional, recomendado:
  - diagrama del árbol de supervisión;
  - diagrama simple de arquitectura cliente-servidor.

---

## 13. Recomendaciones prácticas

- Definir desde el principio la arquitectura general del sistema.
- Separar claramente conexión, dominio y tareas auxiliares.
- Diseñar temprano el protocolo de mensajes entre cliente y servidor.
- Resolver primero el flujo mínimo completo antes de agregar extras.
- Probar pronto las situaciones concurrentes más importantes.
- Probar también temprano el reinicio del servidor con persistencia.
- Documentar desde el inicio.

Pensar la demo en vivo como una secuencia clara de casos que muestre el valor del sistema:

- búsqueda de vuelos;
- ordenamiento por precio;
- entrada a un vuelo;
- visualización de asientos;
- inicio de reserva;
- paso de pago simulado;
- confirmación, cancelación y expiración;
- actualización en tiempo real en múltiples clientes;
- vista del usuario con todas sus reservas;
- reinicio del servidor conservando el estado persistido.
