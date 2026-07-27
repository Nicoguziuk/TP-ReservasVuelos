defmodule Booking.Persistence do
  @moduledoc """
  Proceso (GenServer) único dueño de las tablas DETS del sistema
  (users, flights, reservations). Todos los demás procesos leen y escriben a través de él.
  """

  use GenServer

  # Los 3 tipos de tabla que maneja este proceso. Un solo lugar donde están listados,
  # para no repetirlos en init/1 y en cualquier otro lado que los necesite.
  @kinds [:users, :flights, :reservations]

  # --- API pública ---
  # `server` tiene default __MODULE__ (la instancia real de producción), así el resto
  # del código no necesita pasarlo salvo en tests, donde se usa una instancia aislada.

  def put_user(user, server \\ __MODULE__), do: put(server, :users, user)
  def get_users(server \\ __MODULE__), do: all(server, :users)

  def put_flight(flight, server \\ __MODULE__), do: put(server, :flights, flight)
  def get_flights(server \\ __MODULE__), do: all(server, :flights)

  def put_reservation(reservation, server \\ __MODULE__),
    do: put(server, :reservations, reservation)

  def get_reservations(server \\ __MODULE__), do: all(server, :reservations)

  # --- Auxiliares privadas: arman el mensaje y lo mandan por GenServer.call ---
  # %{id: id} = value: exige que "value" tenga un campo :id, y lo extrae, sin
  # perder el valor completo (structs como %User{}/%Flight{}/%Reservation{} matchean
  # porque son mapas por debajo).
  defp put(server, kind, %{id: id} = value), do: GenServer.call(server, {:put, kind, id, value})
  defp all(server, kind), do: GenServer.call(server, {:all, kind})

  # --- Arranque del proceso ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    # Le pasamos "opts" completo a init/1 (no solo "name"), porque init/1 todavía
    # necesita sacar :dir de ahí.
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    dir = Keyword.get(opts, :dir, Application.get_env(:booking, :data_dir, "data"))
    File.mkdir_p!(dir)

    # Una tabla DETS por kind. El nombre de tabla depende de "name" (la instancia),
    # así dos Persistence corriendo a la vez (ej. en tests async) no chocan archivo.
    tables =
      Map.new(@kinds, fn kind ->
        table = :"#{name}.#{kind}"
        file = dir |> Path.join("#{kind}.dets") |> String.to_charlist()
        {:ok, ^table} = :dets.open_file(table, file: file, type: :set)
        {kind, table}
      end)

    {:ok, %{tables: tables}}
  end

  # --- Callbacks: acá se hace el trabajo real sobre DETS ---

  @impl true
  def handle_call({:put, kind, id, value}, _from, state) do
    :ok = :dets.insert(state.tables[kind], {id, value})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:all, kind}, _from, state) do
    values = :dets.foldl(fn {_id, value}, acc -> [value | acc] end, [], state.tables[kind])
    {:reply, values, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cierra las tablas para que DETS haga flush del archivo a disco.
    Enum.each(state.tables, fn {_kind, table} -> :dets.close(table) end)
    :ok
  end
end
