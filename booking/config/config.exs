import Config

# Carpeta donde Booking.Persistence guarda los archivos DETS (relativa a la del backend).
config :booking, data_dir: "data"

# Sembrar el catálogo inicial de vuelos en el primer arranque (cuando DETS está vacío).
config :booking, seed_on_boot: true

# Tasa de éxito del pago simulado (1.0 = siempre confirma; bajarla fuerza rechazos al azar).
config :booking, payment_success_rate: 1.0

# Puerto del listener HTTP/WebSocket (Cowboy).
config :booking, web_port: 4000

if config_env() == :test do
  # En tests usamos una carpeta temporal y NO sembramos los 60 vuelos en el arranque global
  # (el seed se prueba aislado). Los tests aislados de Persistence usan su propia carpeta.
  # Puerto efímero (0): el listener arranca igual (verifica el embebido) sin chocar puertos.
  config :booking,
    data_dir: Path.join(System.tmp_dir!(), "booking_test_data"),
    seed_on_boot: false,
    web_port: 0
end
