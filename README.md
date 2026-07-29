# TP-ReservasVuelos

Sistema de reserva de asientos en vuelos en tiempo real — Trabajo Práctico Final de Taller de Programación.

Backend en **Elixir/OTP** (WebSocket + GenServers) y frontend en **React + Vite**. Ver [docs/arquitectura.md](docs/arquitectura.md) para el diseño de procesos y [docs/protocolo.md](docs/protocolo.md) para el protocolo de mensajes.

## Estructura del repo

```
booking/    backend Elixir (OTP, WebSocket, persistencia en DETS)
frontend/   frontend React + Vite
docs/       documentación de arquitectura, modelo y protocolo
```

## Requisitos previos

- [Elixir](https://elixir-lang.org/install.html) ~> 1.19 (incluye Erlang/OTP)
- [Node.js](https://nodejs.org/) 20+ y npm

## 1. Instalar dependencias

**Backend:**

```bash
cd booking
mix deps.get
```

**Frontend:**

```bash
cd frontend
npm install
```

## 2. Levantar el backend

```bash
cd booking
mix run --no-halt
```

Levanta el listener WebSocket en `ws://localhost:4000/ws` (puerto configurable en `config/config.exs`, clave `:booking, :web_port`). Los datos (usuarios, vuelos, reservas) persisten en DETS bajo `booking/data/`, así que el estado sobrevive a un reinicio del servidor.

Para bajarlo: `Ctrl+C` dos veces en la terminal.

## 3. Levantar el frontend

En otra terminal:

```bash
cd frontend
npm run dev
```

Sirve la app en `http://localhost:5173`. Se conecta al backend por WebSocket en `ws://localhost:4000/ws` ([src/useBooking.js](frontend/src/useBooking.js)).

> **Importante:** levantar primero el backend y después el frontend, para que el WebSocket conecte apenas se abre la página.

## 4. Correr el sistema completo

Con el backend y el frontend corriendo (pasos 2 y 3), abrí `http://localhost:5173` en el navegador. Podés abrir varias pestañas/navegadores para ver la sincronización en tiempo real entre clientes.

## 5. Correr los tests

El backend tiene la suite de tests (ExUnit):

```bash
cd booking
mix test
```
