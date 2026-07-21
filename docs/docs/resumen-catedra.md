# Resumen — Taller de Programación (Elixir + React)

> Material de consulta teórico-técnico armado a partir de los apuntes de la cátedra (Manuel Camejo). Cubre los fundamentos de **Elixir** (lenguaje funcional, procesos, OTP) y de **React** (componentes funcionales y hooks). Pensado como contexto de referencia: prioriza la teoría completa y conserva los ejemplos de código que fijan sintaxis y patrones.

## Índice

**Parte 1 — Elixir**
1. Fundamentos del lenguaje
2. Abstracción con módulos y procesos
3. Procesos con estado (servers)
4. Generic Server Processes → GenServer
5. OTP básico (Application, Supervisor, árbol de supervisión)

**Parte 2 — React**
6. React funcional (fundamentos)
7. React práctico (mini app con router, fetch y useMemo)

---

# PARTE 1 — ELIXIR

## 1. Fundamentos del lenguaje

### Cambio de paradigma

Elixir es un lenguaje **funcional**. Programar consiste en **transformar datos**, no en mutar estado. En concreto, en Elixir:

- **no hay estado mutable**
- **no hay loops clásicos** (`for`, `while`)
- **no hay objetos**
- **no hay memoria compartida**

Antes de ver concurrencia hay que entender tres cosas: cómo se representan los datos, cómo fluye el código y cómo se transforman los datos.

### Tipos de datos

**Tuplas** — tamaño fijo, acceso rápido. Muy usadas para representar resultados.

```elixir
{:ok, 42}
{:error, :not_found}
```

**Listas** — listas enlazadas, acceso secuencial `O(n)`, construir al frente es `O(1)`.

```elixir
[1, 2, 3]
["hola", "mundo"]
[:a, :b, :c]

[h | t] = [1, 2, 3]
# h = 1
# t = [2, 3]
```

**Maps** — estructura clave → valor, dinámicos, útiles para modelar datos tipo JSON.

```elixir
%{name: "Juan", age: 30}
```

**Keyword lists** — lista de tuplas; mantiene orden y permite claves repetidas.

```elixir
[name: "Juan", age: 30]
[mode: :fast, debug: true, mode: :safe]
```

### Pattern matching

El operador `=` **no asigna**: intenta hacer *match* entre dos expresiones.

```elixir
a = 1        # match básico (liga a = 1)
1 = 1        # ok
1 = 2        # error
```

**Rebinding**: las variables no cambian de valor, se crea un nuevo *binding*.

```elixir
a = 1
a = 2        # nuevo binding, no mutación
```

Match sobre estructuras:

```elixir
# Tuplas
{a, b} = {1, 2}
{:ok, value} = {:ok, 42}

# Listas
[h | t] = [1, 2, 3]
[first, second] = [10, 20]
[first, second] = [10, 20, 30]   # error (no coincide la forma)

# Maps (no hace falta matchear todas las claves)
%{name: name} = %{name: "Juan", age: 30}
%{name: name, age: age} = %{name: "Juan", age: 30}

# Anidado
{:ok, %{name: name}} = {:ok, %{name: "Juan"}}
%{user: %{name: name}} = %{user: %{name: "Ana", age: 20}}

# Ignorar valores con _
{_, b} = {1, 2}
[h | _] = [1, 2, 3]
```

**Pin operator (`^`)** — sirve para matchear contra el valor *ya existente* de una variable, en vez de re-ligarla.

```elixir
a = 1
^a = 1       # ok
^a = 2       # error
```

**En definiciones de funciones** — el comportamiento se define según la *forma* de los datos (varias cláusulas):

```elixir
def classify(0), do: :zero
def classify(1), do: :one
def classify(_), do: :other

def greet(%{name: name}) do
  "Hola #{name}"
end

def extract_ok({:ok, value}) do
  value
end
```

**Guards** — agregan condiciones a una cláusula con `when`:

```elixir
def is_adult(age) when age >= 18, do: true
def is_adult(_), do: false

def sign(x) when x > 0, do: :positive
def sign(0), do: :zero
def sign(x) when x < 0, do: :negative
```

### Inmutabilidad

```elixir
x = 1
x = x + 1    # no muta x: se redefine (nuevo binding)
```

**Consecuencias:** no hay estado compartido, no hay efectos secundarios implícitos, el código es más predecible y es mucho más fácil razonar sobre lo que hace un programa.

### Control de flujo

En Elixir el control de flujo se apoya mucho en pattern matching.

**`case`** — cuando el flujo depende de la *forma* del dato:

```elixir
case x do
  0 -> :zero
  1 -> :one
  _ -> :other
end

case result do
  {:ok, value} -> value
  {:error, _reason} -> :error
end

case user do
  %{name: name, age: age} when age >= 18 -> "#{name} es mayor"
  %{name: name} -> "#{name} es menor"
end
```

**`cond`** — para múltiples condiciones booleanas:

```elixir
cond do
  x > 10 -> :big
  x > 5 -> :medium
  true -> :small
end
```

**`if`** — para casos simples:

```elixir
if x > 0 do
  :positive
else
  :negative
end
```

**Recomendaciones:** preferir pattern matching cuando sea posible; usar `case` cuando el flujo depende de estructuras; usar `cond` para varias condiciones booleanas; usar `if` solo cuando la lógica sea simple.

### Recursión

No existen loops tradicionales: la iteración se expresa con **recursión**. Toda función recursiva tiene un **caso base** y un **caso recursivo**.

```elixir
# suma
def sum([]), do: 0
def sum([h | t]), do: h + sum(t)

# length
def length([]), do: 0
def length([_ | t]), do: 1 + length(t)

# map recursivo
def map([], _fun), do: []
def map([h | t], fun), do: [fun.(h) | map(t, fun)]

# filter recursivo
def filter([], _fun), do: []
def filter([h | t], fun) do
  if fun.(h), do: [h | filter(t, fun)], else: filter(t, fun)
end

# contar pares (con guard)
def count_even([]), do: 0
def count_even([h | t]) when rem(h, 2) == 0, do: 1 + count_even(t)
def count_even([_ | t]), do: count_even(t)
```

### Tail recursion (recursión de cola)

Una función es **tail recursive** cuando la **última operación** es la llamada recursiva. La VM la puede optimizar reutilizando el mismo *stack frame* (uso de memoria constante, similar a un loop eficiente).

**Recursión normal** — deja trabajo pendiente; cada llamada agrega un frame al stack:

```elixir
def sum([]), do: 0
def sum([h | t]), do: h + sum(t)
# sum([1,2,3]) => 1 + (2 + (3 + 0))  ← trabajo pendiente acumulado
```

**Tail recursive** — usa un acumulador; no queda trabajo pendiente:

```elixir
def sum(list), do: sum(list, 0)
def sum([], acc), do: acc
def sum([h | t], acc), do: sum(t, acc + h)
# sum([1,2,3],0) -> sum([2,3],1) -> sum([3],3) -> sum([],6)
```

**Regla práctica:**
- Si aparece `h + recursion(...)` → **no** es tail recursive.
- Si aparece `recursion(..., acc + h)` → **sí** es tail recursive.

Ejemplos optimizados con acumulador:

```elixir
# reverse (la versión con ++ NO es tail recursive y ++ es costoso)
def reverse(list), do: reverse(list, [])
defp reverse([], acc), do: acc
defp reverse([h | t], acc), do: reverse(t, [h | acc])

# length
def length(list), do: length(list, 0)
defp length([], acc), do: acc
defp length([_ | t], acc), do: length(t, acc + 1)

# map (se acumula al frente y se invierte al final)
def map(list, fun), do: map(list, fun, [])
defp map([], _fun, acc), do: Enum.reverse(acc)
defp map([h | t], fun, acc), do: map(t, fun, [fun.(h) | acc])
```

### Fibonacci

**Versión simple** — clara pero recalcula muchísimo y **no** es tail recursive (usa stack, no reutiliza resultados, crece muy mal):

```elixir
def fib(0), do: 0
def fib(1), do: 1
def fib(n) when n > 1, do: fib(n - 1) + fib(n - 2)
```

**Versión tail recursive** — en vez de recalcular, pasa el estado como parámetros (`a` = término anterior, `b` = término actual). El compilador la optimiza:

```elixir
def fib(0), do: 0
def fib(1), do: 1
def fib(n), do: fib(n, 0, 1)

defp fib(1, _a, b), do: b
defp fib(n, a, b), do: fib(n - 1, b, a + b)
# fib(5,0,1) -> fib(4,1,1) -> fib(3,1,2) -> fib(2,2,3) -> fib(1,3,5) => 5
```

### Enum y `reduce`

Recorrer listas "a mano" con recursión muestra cómo funciona el lenguaje, pero en código real se usa el módulo **`Enum`**, que da abstracciones ya hechas para recorrer y transformar colecciones. Funciones principales:

- `map` → transforma cada elemento de la colección (**conserva cardinalidad**)
- `filter` → selecciona algunos elementos (**cambia cardinalidad**)
- `reduce` → acumula resultados (**es la abstracción más general**)

`reduce` puede expresar cualquier transformación; de hecho `map` y `filter` se pueden escribir solo con `reduce`:

```elixir
# map con reduce
def map(list, fun) do
  list
  |> Enum.reduce([], fn x, acc -> [fun.(x) | acc] end)
  |> Enum.reverse()
end

# filter con reduce
def filter(list, fun) do
  list
  |> Enum.reduce([], fn x, acc ->
    if fun.(x), do: [x | acc], else: acc
  end)
  |> Enum.reverse()
end
```

### Pipeline (`|>`)

El operador pipe encadena transformaciones: el resultado de un paso pasa como **primer argumento** de la función siguiente. Convierte la composición anidada (que se lee de adentro hacia afuera) en una lectura lineal.

```elixir
value |> function()      # equivale a function(value)

"hola" |> String.upcase()             # String.upcase("hola")

"hola"
|> String.upcase()
|> String.reverse()                   # String.reverse(String.upcase("hola"))
```

**Regla clave:** el valor de la izquierda se pasa como primer argumento.

```elixir
[1, 2, 3, 4]
|> Enum.filter(fn x -> rem(x, 2) == 0 end)
|> Enum.map(fn x -> x * 2 end)
```

**El orden importa** (`map` luego `filter` ≠ `filter` luego `map`). Con función propia se puede usar la captura `&nombre/aridad`:

```elixir
def double(x), do: x * 2

[1, 2, 3] |> Enum.map(&double/1)
```

**Múltiples argumentos:** el pipe solo inserta el valor como primer argumento. Si la función necesita más, se envuelve en una función anónima:

```elixir
list
|> Enum.map(fn x -> my_fun(x, extra) end)
```

**Recomendaciones:** usar pipes cuando hay varias transformaciones; mantener cada paso simple; evitar pipes cuando no mejoran legibilidad; preferir separar `filter` + `map` en pasos antes que meter lógica condicional dentro de un `map`.

### Cierre de fundamentos

Elixir se apoya en: datos inmutables, pattern matching, control de flujo basado en estructuras, recursión, pipelines y transformación de datos. Son la base para entender después procesos, paso de mensajes, GenServer y OTP: en Elixir la concurrencia no es algo separado del lenguaje, se construye sobre estos fundamentos.

---

## 2. Abstracción con módulos y procesos

### Idea central

Primero se modela una abstracción real con **funciones puras** (datos + módulos). Después esa abstracción puede **vivir dentro de un proceso**, comunicándose por mensajes y manteniendo estado en un loop. En Elixir, una abstracción se construye con **datos + módulos**; cuando hay concurrencia, ese estado puede vivir en un proceso al que **no se accede por memoria compartida sino por paso de mensajes**.

### Modelado de dominio con structs

Ejemplo conductor: una tienda online (`Shop`) con productos y carritos.

```elixir
defmodule Product do
  defstruct [:id, :name, :price, :stock]
end

defmodule Cart do
  defstruct [:id, items: %{}]
end

defmodule Shop do
  defstruct next_product_id: 1,
            next_cart_id: 1,
            products: %{},
            carts: %{}
end
```

El dominio queda explícito; cada struct representa una entidad; **no hay clases ni objetos**; siguen siendo datos inmutables.

### La abstracción vive en el módulo (no es OO)

En Elixir la lógica no vive "dentro del objeto", vive en **funciones de módulo**. No se hace `shop.add_product(...)` sino `Shop.add_product(shop, ...)`. La abstracción está en la representación de datos + la API del módulo.

```elixir
defmodule Shop do
  defstruct next_product_id: 1, next_cart_id: 1, products: %{}, carts: %{}

  def new, do: %Shop{}

  def add_product(%Shop{} = shop, attrs) do
    product = %Product{
      id: shop.next_product_id,
      name: attrs.name,
      price: attrs.price,
      stock: attrs.stock
    }

    %Shop{
      shop
      | next_product_id: shop.next_product_id + 1,
        products: Map.put(shop.products, product.id, product)
    }
  end

  def new_cart(%Shop{} = shop) do
    cart = %Cart{id: shop.next_cart_id, items: %{}}
    new_shop = %Shop{
      shop
      | next_cart_id: shop.next_cart_id + 1,
        carts: Map.put(shop.carts, cart.id, cart)
    }
    {new_shop, cart.id}
  end
end
```

Conceptos que aparecen: pattern matching en argumentos, construcción de structs, **actualización inmutable** (sintaxis `%Struct{viejo | campo: nuevo}`), generación de IDs, `Map.put/3`.

### Actualización inmutable de datos jerárquicos

La tienda no es un dato plano: tiene jerarquía (`Shop` → `carts` → `items` → cantidades por producto). Para actualizar algo anidado hay que **buscar, actualizar y reconstruir** cada nivel; nunca se muta la estructura original, se construye una nueva versión.

```elixir
def add_to_cart(%Shop{} = shop, cart_id, product_id, quantity) do
  cart = Map.fetch!(shop.carts, cart_id)

  new_items =
    Map.update(cart.items, product_id, quantity, fn old_qty ->
      old_qty + quantity
    end)

  new_cart = %Cart{cart | items: new_items}
  %Shop{shop | carts: Map.put(shop.carts, cart_id, new_cart)}
end

def cart_total(%Shop{} = shop, cart_id) do
  cart = Map.fetch!(shop.carts, cart_id)

  cart.items
  |> Enum.map(fn {product_id, quantity} ->
    product = Map.fetch!(shop.products, product_id)
    product.price * quantity
  end)
  |> Enum.sum()
end

def checkout(%Shop{} = shop, cart_id) do
  cart = Map.fetch!(shop.carts, cart_id)

  new_products =
    Enum.reduce(cart.items, shop.products, fn {product_id, quantity}, products_acc ->
      product = Map.fetch!(products_acc, product_id)
      updated_product = %Product{product | stock: product.stock - quantity}
      Map.put(products_acc, product_id, updated_product)
    end)

  new_carts = Map.delete(shop.carts, cart_id)
  %Shop{shop | products: new_products, carts: new_carts}
end
```

### El problema: race conditions

Mientras `Shop` es solo un dato puro, el modelo es claro y seguro. Pero si varias partes del sistema operan "al mismo tiempo" sobre ese estado, aparece una **race condition**:

- dos clientes leen la misma versión del estado,
- ambos deciden que su operación es válida,
- ambos escriben una nueva versión,
- una operación pisa a la otra.

Una race condition ocurre cuando el resultado depende del **orden exacto** en que se ejecutan operaciones concurrentes, varias operaciones acceden al mismo estado lógico, y no hay coordinación clara. El problema no es "que pasen muchas cosas", sino que **varias operaciones compiten por decidir el próximo estado**.

### Comparación con el modelo de memoria compartida (locks)

En modelos con memoria compartida (p. ej. threads en Java), varios threads acceden al mismo objeto y hay que coordinar con **locks / mutexes / `synchronized`**: solo una ejecución entra a la vez a la sección crítica.

```java
class Inventory {
    private int stock;
    public synchronized boolean buyOne() {
        if (stock > 0) { stock = stock - 1; return true; }
        return false;
    }
}
```

### El enfoque de Elixir: estado aislado + mensajes

En Elixir no se comparte memoria ni se usan locks. En su lugar:

- el estado **vive dentro de un proceso**,
- ese proceso es el **único dueño** del estado,
- otros procesos **no tocan** ese estado directamente,
- solo pueden **pedir operaciones enviando mensajes**.

La pregunta deja de ser "¿cómo evito que dos threads toquen la misma memoria?" y pasa a ser "**¿qué proceso es dueño del estado y qué mensajes acepta?**".

**¿Por qué no hacen falta locks?** Porque no hay memoria compartida mutable entre procesos. Cada proceso BEAM tiene su propia memoria, no puede modificar la de otro, y se comunica solo por mensajes. El modelo natural no es *shared state + locks* sino **isolated state + message passing**.

### Proceso vs objeto

Un proceso con estado se *parece* a un objeto (mantiene estado interno, expone operaciones, representa una entidad que responde pedidos), pero la diferencia es grande:

| Objeto (OO clásico) | Proceso (Elixir) |
|---|---|
| Suele vivir en memoria compartida | Vive aislado, con memoria propia |
| Varios threads pueden usarlo a la vez | Otros procesos no tocan su estado |
| Necesita sincronización si hay concurrencia | Se interactúa enviando mensajes |
| Sus métodos se invocan directamente | Procesa operaciones secuencialmente desde su mailbox |

Un proceso **no es "un objeto en otro lenguaje"**: es una **unidad de concurrencia autónoma**.

### Procesos BEAM

Un proceso BEAM **no** es un proceso del sistema operativo: es muy liviano, tiene su propia memoria, tiene una **mailbox** y se comunica por mensajes.

```elixir
# crear un proceso
pid = spawn(fn -> IO.puts("Hola desde otro proceso") end)

# enviar y recibir mensajes
pid =
  spawn(fn ->
    receive do
      message -> IO.inspect(message)
    end
  end)

send(pid, {:hello, "world"})
```

**`receive`** espera mensajes en la mailbox, intenta matchear patrones y, si no encuentra uno, sigue esperando. Admite `after` para timeout:

```elixir
receive do
  msg -> IO.inspect(msg)
after
  10000 -> IO.puts("timeout")
end
```

**Request / response manual** — para pedir algo y esperar respuesta hay que mandar el mensaje incluyendo *quién es el caller* (`self()`) y que el proceso le responda:

```elixir
server =
  spawn(fn ->
    receive do
      {:ping, caller} -> send(caller, :pong)
    end
  end)

send(server, {:ping, self()})
receive do
  msg -> IO.inspect(msg)
end
```

### Un proceso útil necesita un loop recursivo

Si un proceso hace un solo `receive`, atiende un mensaje y termina. Para seguir vivo necesita un **loop recursivo** (acá vuelve la recursión de los fundamentos):

```elixir
def loop do
  receive do
    msg ->
      IO.inspect(msg)
      loop()
  end
end
```

### Mover el estado a un proceso: `ShopServer`

Un proceso mantiene internamente un `%Shop{}`: arranca con un estado inicial, recibe mensajes, actualiza el estado y sigue con un nuevo loop. El caller ya no toca el estado, solo manda mensajes.

```elixir
defmodule ShopServer do
  def start do
    spawn(fn -> loop(Shop.new()) end)
  end

  def loop(shop) do
    receive do
      {:new_cart, caller} ->
        {new_shop, cart_id} = Shop.new_cart(shop)
        send(caller, {:cart_created, cart_id})
        loop(new_shop)

      {:add_product, attrs} ->
        new_shop = Shop.add_product(shop, attrs)
        loop(new_shop)

      {:get_product, product_id, caller} ->
        product = Map.get(shop.products, product_id)
        send(caller, {:product, product})
        loop(shop)

      {:add_to_cart, cart_id, product_id, quantity} ->
        new_shop = Shop.add_to_cart(shop, cart_id, product_id, quantity)
        loop(new_shop)

      {:checkout, cart_id} ->
        new_shop = Shop.checkout(shop, cart_id)
        loop(new_shop)
    end
  end
end
```

### Cómo el proceso evita las race conditions

Cuando `%Shop{}` vive dentro de `ShopServer`: solo `ShopServer` decide el próximo estado, nadie más modifica `products`/`carts` directamente, y todas las operaciones llegan como mensajes que el loop **procesa de a una**. Si dos clientes mandan `{:checkout, ...}` "a la vez", el proceso no ejecuta ambas en paralelo: recibe una, actualiza el estado, y la segunda se evalúa **sobre el estado ya actualizado**. El proceso actúa como un **serializador natural** de operaciones; la consistencia aparece porque hay un único dueño del estado, el acceso es secuencial y el estado no se comparte.

### Registrar un proceso con nombre

En vez de guardar el PID, se puede registrar el proceso con un nombre (átomo):

```elixir
pid = spawn(fn -> ShopServer.loop(Shop.new()) end)
Process.register(pid, :shop_server)

send(:shop_server, {:add_product, %{name: "Mouse", price: 20000, stock: 10}})
```

### Línea argumental

Modelamos una tienda con datos inmutables → definimos una API con funciones de módulo → actualizamos estado reconstruyendo estructuras → detectamos el problema de concurrencia → movimos el estado a un proceso → interactuamos por mensajes. Esa es la base conceptual de OTP. El paso siguiente natural (hacer esto de forma estándar y robusta) es **`GenServer`**.

---

## 3. Procesos con estado (servers)

Esta sección integra todo lo anterior: un proceso puede administrar **estado con forma** (una estructura de dominio completa), no solo valores sueltos, y cada mensaje transforma esa estructura devolviendo una nueva versión.

### Ejemplo conductor: Biblioteca

Entidades y operaciones (crear biblioteca, agregar/sacar/consultar libro, prestar, devolver, listar disponibles):

```elixir
defmodule Book do
  defstruct [:id, :title, :author, available: true]
end

defmodule User do
  defstruct [:id, :name]
end

defmodule Library do
  defstruct next_book_id: 1,
            next_user_id: 1,
            books: %{},
            users: %{},
            loans: %{}

  def new, do: %Library{}
end
```

### API pura del módulo

```elixir
def add_book(%Library{} = library, attrs) do
  book = %Book{
    id: library.next_book_id,
    title: attrs.title,
    author: attrs.author,
    available: true
  }

  %Library{
    library
    | next_book_id: library.next_book_id + 1,
      books: Map.put(library.books, book.id, book)
  }
end

def add_user(%Library{} = library, attrs) do
  user = %User{id: library.next_user_id, name: attrs.name}

  %Library{
    library
    | next_user_id: library.next_user_id + 1,
      users: Map.put(library.users, user.id, user)
  }
end

def get_book(%Library{} = library, id), do: Map.get(library.books, id)

def remove_book(%Library{} = library, id) do
  %Library{library | books: Map.delete(library.books, id)}
end

def available_books(%Library{} = library) do
  library.books
  |> Map.values()
  |> Enum.filter(fn %Book{available: available} -> available end)
end
```

### Modelado de préstamos e invariantes

Los préstamos **no** son un struct separado: se modelan como una relación dentro de `Library` en el map `loans`, con la convención **clave = `book_id`, valor = `user_id`**. Así `2 => 1` significa "el libro 2 está prestado al usuario 1".

Esto prioriza claridad, pocas entidades y una **única fuente de verdad**. **Invariantes** que el modelo debe preservar:

1. un libro solo puede estar prestado a un usuario a la vez,
2. si un libro está en `loans`, no está disponible,
3. si un libro no está en `loans`, puede estar disponible,
4. prestar y devolver deben mantener consistente la relación entre `books` y `loans`.

```elixir
def lend_book(%Library{} = library, user_id, book_id) do
  cond do
    not Map.has_key?(library.users, user_id) ->
      {:error, :user_not_found}

    not Map.has_key?(library.books, book_id) ->
      {:error, :book_not_found}

    Map.has_key?(library.loans, book_id) ->
      {:error, :already_lent}

    true ->
      book = Map.fetch!(library.books, book_id)
      updated_book = %Book{book | available: false}

      new_library = %Library{
        library
        | books: Map.put(library.books, book_id, updated_book),
          loans: Map.put(library.loans, book_id, user_id)
      }

      {:ok, new_library}
  end
end

def return_book(%Library{} = library, book_id) do
  case Map.get(library.loans, book_id) do
    nil ->
      {:error, :not_lent}

    _user_id ->
      book = Map.fetch!(library.books, book_id)
      updated_book = %Book{book | available: true}

      new_library = %Library{
        library
        | books: Map.put(library.books, book_id, updated_book),
          loans: Map.delete(library.loans, book_id)
      }

      {:ok, new_library}
  end
end

def user_loans(%Library{} = library, user_id) do
  library.loans
  |> Enum.filter(fn {_book_id, borrowed_by} -> borrowed_by == user_id end)
  |> Enum.map(fn {book_id, _user_id} -> Map.fetch!(library.books, book_id) end)
end
```

Las operaciones que pueden fallar devuelven tuplas `{:ok, new_library}` / `{:error, reason}`. No se modifica la estructura original: se construye una nueva versión consistente.

### El proceso: `LibraryServer`

El estado del proceso es un `%Library{}` completo (no "variables sueltas", sino una abstracción entera). El loop recibe mensajes, aplica una transformación y vuelve a `loop(nuevo_estado)`.

```elixir
defmodule LibraryServer do
  def start do
    spawn(fn -> loop(Library.new()) end)
  end

  def loop(library) do
    receive do
      {:add_book, attrs} ->
        loop(Library.add_book(library, attrs))

      {:add_user, attrs} ->
        loop(Library.add_user(library, attrs))

      {:get_book, id, caller} ->
        send(caller, {:book, Library.get_book(library, id)})
        loop(library)

      {:lend_book, user_id, book_id, caller} ->
        case Library.lend_book(library, user_id, book_id) do
          {:ok, new_library} ->
            send(caller, :ok)
            loop(new_library)

          {:error, reason} ->
            send(caller, {:error, reason})
            loop(library)
        end

      {:return_book, book_id, caller} ->
        case Library.return_book(library, book_id) do
          {:ok, new_library} ->
            send(caller, :ok)
            loop(new_library)

          {:error, reason} ->
            send(caller, {:error, reason})
            loop(library)
        end

      {:user_loans, user_id, caller} ->
        send(caller, {:loans, Library.user_loans(library, user_id)})
        loop(library)

      {:remove_book, id} ->
        loop(Library.remove_book(library, id))
    end
  end
end
```

### Cómo procesa mensajes (mailbox secuencial)

El proceso tiene una mailbox; el `receive` atiende los mensajes **de a uno**:

1. llega un mensaje,
2. el proceso lo pattern-matchea,
3. aplica una transformación sobre el estado actual,
4. obtiene una nueva versión del `%Library{}`,
5. entra otra vez en `loop(new_state)`.

```
mensaje 1 ---> mailbox ---┐
mensaje 2 ---> mailbox ---┼--> receive --> transformar estado --> loop(nuevo_estado)
mensaje 3 ---> mailbox ---┘
```

No hay dos transformaciones a la vez sobre la misma biblioteca: hay una **secuencia** de mensajes atendidos por el mismo proceso. Si dos usuarios piden el mismo libro al mismo tiempo, el primero actualiza `loans` y el segundo, evaluado sobre el estado nuevo, falla con `{:error, :already_lent}`.

### Trade-off: este modelo también tiene costos

Tener un único proceso dueño del estado simplifica la consistencia (evita shared mutable state, evita locks, reduce race conditions, serializa operaciones), pero por eso mismo introduce costos:

- **Mailbox creciendo:** si los mensajes llegan más rápido de lo que el proceso puede atender, la mailbox crece, sube la latencia y el proceso se atrasa.
- **Un solo punto caliente:** aunque la VM tenga muchos schedulers, este proceso ejecuta **una operación por vez** (cuello de botella; el paralelismo está del lado de los clientes, el acceso al estado se serializa en el servidor).
- **Proceso demasiado grande:** si concentra demasiadas responsabilidades (libros, usuarios, préstamos, búsquedas, reportes, lógica pesada) se vuelve lento y difícil de escalar.
- **Único punto de falla lógica:** cualquier bug o lentitud ahí afecta a toda esa unidad del sistema.

### Cómo se resuelve (no con locks, sino con diseño)

- **Estrategia 1 — particionar el estado:** en vez de un solo proceso para toda la biblioteca, usar un coordinador + un proceso por libro / por usuario / por subconjunto del dominio. Reduce contención y gana paralelismo real.
- **Estrategia 2 — separar lectura de escritura:** escribir requiere serialización, pero leer puede escalar con otros mecanismos; no siempre tienen que pasar por el mismo camino.
- **Estrategia 3 — no meter trabajo pesado en el proceso dueño del estado:** nada de parsing pesado, IO lento, llamadas externas o cálculos largos (mientras los hace, no atiende su mailbox). Regla práctica: **el dueño del estado debe decidir rápido y delegar el trabajo pesado**.

**Idea de diseño:** un proceso dueño del estado no es la solución final a toda concurrencia, es una **unidad de consistencia**; después hay que decidir cuán grande o chica debe ser esa unidad.

---

## 4. Generic Server Processes → GenServer

### El patrón repetitivo

Los server process manuales repiten siempre la misma estructura: crear un proceso, entrar en un loop infinito, mantener estado, recibir mensajes, decidir qué hacer y responder cuando corresponde.

```elixir
def start do
  spawn(fn -> loop(initial_state()) end)
end

def loop(state) do
  receive do
    {:some_request, caller, data} ->
      {response, new_state} = handle_request(state, data)
      send(caller, response)
      loop(new_state)
  end
end
```

Lo que **no** cambia entre un server y otro: cómo spawnear, cómo hacer el loop, cómo mandar una respuesta. Lo que **sí** cambia: cómo se inicializa el estado, cómo se maneja cada mensaje, qué respuesta se devuelve y cómo evoluciona el estado.

### Parte genérica vs. parte específica

Un *generic server process* encapsula la parte repetitiva. Se separa en dos módulos:

- **Módulo genérico** → la mecánica: spawn, loop infinito, recepción de mensajes, envío de respuestas, *threading* del estado.
- **Módulo callback** → la lógica del dominio: cómo inicializar el estado, cómo manejar cada request, qué respuesta devolver, qué nuevo estado producir.

El módulo callback "se enchufa" en el genérico implementando ciertas funciones.

### `ServerProcess` casero (versión con call y cast)

```elixir
defmodule ServerProcess do
  def start(callback_module) do
    spawn(fn ->
      initial_state = callback_module.init()
      loop(callback_module, initial_state)
    end)
  end

  def call(server_pid, request) do
    send(server_pid, {:call, request, self()})
    receive do
      {__MODULE__, response} -> response
    end
  end

  def cast(server_pid, request) do
    send(server_pid, {:cast, request})
  end

  defp loop(callback_module, state) do
    receive do
      {:call, request, caller} ->
        {response, new_state} = callback_module.handle_call(request, state)
        send(caller, {__MODULE__, response})
        loop(callback_module, new_state)

      {:cast, request} ->
        new_state = callback_module.handle_cast(request, state)
        loop(callback_module, new_state)
    end
  end
end
```

### Call vs cast

- **Call** → interacción **síncrona**: el caller manda un mensaje y **espera** respuesta.
- **Cast** → interacción **asíncrona** (fire-and-forget): el caller manda un mensaje y **no espera** respuesta, sigue con su ejecución.

Callback concreto (key-value store): la infraestructura sigue siendo genérica; lo único que cambia entre dominios es el callback.

```elixir
defmodule KeyValueStore do
  def start, do: ServerProcess.start(__MODULE__)

  def put(pid, key, value), do: ServerProcess.cast(pid, {:put, key, value})
  def get(pid, key), do: ServerProcess.call(pid, {:get, key})

  def init, do: %{}

  def handle_cast({:put, key, value}, state) do
    Map.put(state, key, value)
  end

  def handle_call({:get, key}, state) do
    {Map.get(state, key), state}
  end
end
```

### Behaviour

En Erlang/OTP un **behaviour** es código genérico que implementa un patrón común: expone un contrato y otro módulo se enchufa implementando *callbacks*. `ServerProcess` es un ejemplo simple de behaviour (`ServerProcess` = comportamiento genérico; `Counter`/`KeyValueStore` = implementación concreta).

### GenServer

`GenServer` es la implementación real, completa y robusta de esta idea. **No es magia** ni inventa otro modelo de concurrencia: sigue apoyándose en procesos, mensajes, estado y callbacks. Agrega soporte para calls, casts, timeouts, propagación de crashes, etc. Para código real conviene usarlo en vez de mantener una versión casera.

```elixir
defmodule KeyValueStore do
  use GenServer

  def start, do: GenServer.start(__MODULE__, nil)

  def put(pid, key, value), do: GenServer.cast(pid, {:put, key, value})
  def get(pid, key), do: GenServer.call(pid, {:get, key})

  def init(_), do: {:ok, %{}}

  def handle_cast({:put, key, value}, state) do
    {:noreply, Map.put(state, key, value)}
  end

  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state, key), state}
  end
end
```

**Callbacks más usados** y sus tuplas de retorno:

- `init/1` → estado inicial; retorna `{:ok, estado}`.
- `handle_call/3` → requests síncronos (que esperan respuesta); recibe `(request, from, state)` y retorna `{:reply, respuesta, nuevo_estado}`.
- `handle_cast/2` → requests asíncronos (fire-and-forget); retorna `{:noreply, nuevo_estado}`.
- `handle_info/2` → mensajes que no son call ni cast.

Lectura conceptual: `GenServer.call` = síncrono, `GenServer.cast` = asíncrono, `init` = estado inicial, `handle_call` = requests con respuesta, `handle_cast` = fire-and-forget.

**Qué no cambia con GenServer:** sigue habiendo un proceso, con estado privado, mensajes, requests atendidas de a una y estado que evoluciona con cada request. GenServer **no reemplaza el modelo, encapsula la infraestructura repetitiva** del modelo.

### Otras abstracciones construidas sobre procesos

**Agent** — encapsula estado de forma simple, cuando no se necesita toda la flexibilidad de un GenServer:

```elixir
defmodule Counter do
  def start, do: Agent.start(fn -> 0 end)
  def increment(pid), do: Agent.update(pid, fn state -> state + 1 end)
  def get(pid), do: Agent.get(pid, fn state -> state end)
end
```

**Task** — trabajo puntual que corre en otro proceso y luego termina (cálculos, requests, tareas temporales). No está pensado para mantener estado a largo plazo; a veces alcanza una función anónima sin definir módulo:

```elixir
task = Task.async(fn -> Enum.sum(1..10) end)
result = Task.await(task)

# fire-and-forget
Task.start(fn -> IO.puts("doing work") end)
```

**Supervisor** — arranca, monitorea y reinicia procesos de forma estructurada. No resuelve lógica de dominio, resuelve **organización y tolerancia a fallos** (ver sección 5).

### Cuadro comparativo

| Abstracción | Sirve para | Estado propio | Vive mucho tiempo | Ejemplo típico |
|---|---|---|---|---|
| **Agent** | Encapsular estado simple | Sí | Sí | contador, caché simple |
| **Task** | Trabajo puntual | No relevante | No | cálculo, request, worker temporal |
| **GenServer** | Proceso con estado y protocolo más rico | Sí | Sí | store, registry, coordinator |
| **Supervisor** | Organizar y reiniciar procesos | No de dominio | Sí | árbol de procesos OTP |

**Idea final:** la pregunta clave no es solo "cómo usar GenServer", sino **qué parte de un server process pertenece a la infraestructura genérica y qué parte pertenece al dominio**. Cuando eso queda claro, GenServer deja de ser una caja negra.

---

## 5. OTP básico (Application, Supervisor, árbol de supervisión)

### Qué es OTP

**OTP** (Open Telecom Platform) viene de Ericsson, del mundo de las telecomunicaciones: sistemas distribuidos, muchos procesos concurrentes, servicios que no podían caerse, necesidad de tolerar fallos y de operar sistemas grandes mucho tiempo. OTP es una **forma estandarizada de construir sistemas concurrentes y tolerantes a fallos** sobre la VM de Erlang. No cambia el modelo (siguen existiendo procesos, mensajes, estado, callbacks): agrega una capa de **organización** reusable y robusta.

Resuelve preguntas como: si tengo varios procesos importantes, ¿quién los arranca?, ¿quién los supervisa?, ¿qué pasa si uno falla?, ¿cómo organizo todo sin hacerlo a mano?

### Las 3 piezas

- **`GenServer`** — un proceso con estado y callbacks conocidos (lógica de dominio).
- **`Supervisor`** — un proceso especial cuyo trabajo **no** es lógica de negocio sino **infraestructura**: arrancar hijos, monitorearlos y reiniciarlos si fallan.
- **`Application`** — el **punto de entrada** de la aplicación OTP; al arrancar construye el árbol principal de procesos.

### Qué es un supervisor

Un supervisor es un proceso OTP especializado en manejar otros procesos. Su responsabilidad: arrancar procesos hijos, saber cuáles son, observar si alguno muere y decidir si reiniciarlo. Esto separa dos tipos de lógica:

- **Lógica de dominio** (guardar tareas, contar eventos, registrar auditoría).
- **Lógica de infraestructura** (arrancar procesos, reiniciarlos si fallan, mantener el sistema vivo).

### Proyecto OTP básico

```bash
mix new otp_demo --sup
```

La opción `--sup` genera una aplicación OTP básica con un módulo de entrada:

```elixir
defmodule NebulaCore.Application do
  use Application

  def start(_type, _args) do
    children = []
    opts = [strategy: :one_for_one, name: NebulaCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

- `use Application` → el módulo es el punto de entrada de la app.
- `children` → lista de procesos hijos a arrancar.
- `Supervisor.start_link` → arranca un supervisor como proceso principal.
- `strategy: :one_for_one` → si un hijo falla, se reinicia **solo ese** hijo.

### GenServers de ejemplo (con `start_link/1` para supervisión)

Para ser supervisables, los GenServer implementan `start_link/1` y se registran por nombre de módulo. Patrón común (incluye un `crash/0` para demostrar reinicio):

```elixir
defmodule NebulaCore.TodoListServer do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def add(item), do: GenServer.cast(__MODULE__, {:add, item})
  def all, do: GenServer.call(__MODULE__, :all)
  def crash, do: GenServer.cast(__MODULE__, :crash)

  @impl true
  def init(_arg), do: {:ok, []}

  @impl true
  def handle_cast({:add, item}, state), do: {:noreply, [item | state]}

  @impl true
  def handle_cast(:crash, _state), do: raise "TodoListServer crashed on purpose"

  @impl true
  def handle_call(:all, _from, state), do: {:reply, Enum.reverse(state), state}
end
```

(`StatsServer` mantiene un contador entero con `increment`/`get`; `AuditServer` mantiene una lista de logs con `log`/`all`. Mismo patrón: `start_link/1`, `init/1`, `handle_cast/2`, `handle_call/3`.)

### Cómo se arma el árbol de supervisión

Se construye **de arriba hacia abajo**: arranca la `Application`, esta arranca un supervisor principal, y ese supervisor arranca a sus hijos.

```elixir
defmodule NebulaCore.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NebulaCore.TodoListServer,
      NebulaCore.StatsServer,
      NebulaCore.AuditServer
    ]

    opts = [strategy: :one_for_one, name: NebulaCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

```
NebulaCore.Application
└── NebulaCore.Supervisor
    ├── NebulaCore.TodoListServer
    ├── NebulaCore.StatsServer
    └── NebulaCore.AuditServer
```

Cada módulo hijo implementa `start_link/1`, así el supervisor sabe cómo arrancarlo, y cada uno queda bajo supervisión. Los procesos no quedan "sueltos": quedan organizados dentro de una estructura donde alguien los arranca y los vigila. Para sistemas grandes, un supervisor puede arrancar **otros supervisores** (subárboles especializados).

### Estrategia `:one_for_one`

Es la más simple: **si un hijo falla, se reinicia solo ese hijo**; los demás no se reinician.

```
... TodoListServer
... StatsServer   <-- falla y luego es reiniciado (los otros siguen igual)
... AuditServer
```

Ejemplos clásicos de uso de supervisores: servers con estado (caches, registries, stores, coordinadores), procesos de infraestructura (connection pools, pub/sub, trackers, task supervisors) y subárboles especializados.

### Reinicio: crash y recuperación

En `iex -S mix` se puede forzar un crash y observar el reinicio:

```elixir
pid_before = Process.whereis(NebulaCore.StatsServer)
NebulaCore.StatsServer.crash()
Process.sleep(100)
pid_after = Process.whereis(NebulaCore.StatsServer)

pid_before == pid_after   # => false (es un proceso nuevo, otro PID)
```

Qué pasó: el proceso crasheó, el supervisor detectó la caída y (con `:one_for_one`) reinició **solo ese** proceso, que ahora tiene **otro PID**.

**Punto importante — reiniciar NO es "seguir donde estaba".** Reiniciar significa crear un proceso nuevo, volver a ejecutar `init/1` y **arrancar desde cero**, salvo que haya persistencia externa. Por eso, tras el reinicio, el estado vuelve al inicial (`StatsServer.get()` vuelve a `0`).

### Testing del comportamiento

Test simple de funcionamiento con ExUnit:

```elixir
defmodule NebulaCore.TodoListServerTest do
  use ExUnit.Case

  test "adds and returns items" do
    NebulaCore.TodoListServer.add("item 1")
    NebulaCore.TodoListServer.add("item 2")
    assert NebulaCore.TodoListServer.all() == ["item 1", "item 2"]
  end
end
```

**Problema:** usar los procesos reales globales hace que los tests se interfieran y el estado quede sucio. Conviene poder arrancar procesos **aislados**, parametrizando el nombre en `start_link`:

```elixir
def start_link(opts \\ []) do
  name = Keyword.get(opts, :name, __MODULE__)
  GenServer.start_link(__MODULE__, 0, name: name)
end
```

Test de **reinicio bajo supervisor** (con un supervisor ad hoc dentro del test):

```elixir
defmodule NebulaCore.SupervisionTest do
  use ExUnit.Case

  test "restarts a crashed child" do
    children = [{NebulaCore.StatsServer, name: :stats_test}]
    {:ok, _sup} = Supervisor.start_link(children, strategy: :one_for_one)

    pid_before = Process.whereis(:stats_test)

    GenServer.cast(:stats_test, :crash)
    Process.sleep(100)

    pid_after = Process.whereis(:stats_test)

    assert pid_before != pid_after          # reinició (cambió el PID)
    assert GenServer.call(:stats_test, :get) == 0   # estado volvió al inicial
  end
end
```

### Qué queda fuera de esta intro

No se profundiza (todavía) en: estrategias `:rest_for_one` / `:one_for_all`, `DynamicSupervisor`, `Task.Supervisor`, árboles complejos, ni persistencia para recuperar estado tras reinicio.

**Idea final de OTP:** la pregunta deja de ser "¿cómo escribo un proceso?" y pasa a ser **"¿cómo organizo varios procesos para que formen una aplicación robusta?"** — cada uno con una responsabilidad (unos manejan dominio, otros infraestructura) dentro de una estructura que puede recuperarse de fallos.

---

# PARTE 2 — REACT

## 6. React funcional (fundamentos)

### Idea central

**React es una librería de JavaScript para construir interfaces de usuario.** Su foco no es "hacer páginas completas" sino resolver un problema concreto: construir y actualizar interfaces complejas sin terminar con código desordenado y lleno de manipulación manual del DOM.

En apps chicas, tocar el DOM a mano parece manejable; pero cuando la UI crece aparecen problemas: múltiples partes de la pantalla dependen del mismo estado, distintos eventos disparan cambios en distintos lugares, hay que esconder/mostrar/reemplazar/reordenar elementos, y la lógica de negocio se mezcla con la visual. React propone: **describir la interfaz a partir del estado actual**, dividir la UI en **componentes**, y **recalcular** qué debería verse cuando cambia el estado.

La intuición clave:

```
UI = f(state)
```

No se piensa la UI como una secuencia de instrucciones ("crear botón, cambiar texto, agregarlo al DOM, esconderlo..."), sino como: **dado un estado, ¿qué interfaz debería verse?** Si el estado cambia, cambia el resultado de esa función y por lo tanto lo que se renderiza. Esto conecta bien con la programación funcional.

### El stack web y dónde entra React

- **HTML** → estructura del contenido (títulos, párrafos, botones, listas, formularios).
- **CSS** → presentación visual (colores, tamaños, espaciados, layout, responsive).
- **JavaScript** → comportamiento y lógica en el navegador (clicks, validaciones, requests HTTP, contenido dinámico).

React **corre sobre JavaScript** y no reemplaza a HTML/CSS/JS: usa JS como lenguaje base, genera estructuras que terminan renderizándose como HTML y convive con CSS. **React organiza cómo construir UI sobre JavaScript.**

### Server-side rendering (SSR) vs client-side rendering (CSR)

- **SSR:** el servidor genera el HTML ya armado y se lo manda al navegador. Ventajas: primera carga rápida, contenido visible rápido, SEO más simple. Costo: más trabajo del servidor; la interactividad compleja requiere más pasos.
- **CSR:** el navegador recibe una base mínima y JavaScript construye/actualiza la interfaz del lado del cliente (típico de las **SPAs**). Ventajas: interfaces muy dinámicas, sensación de "app", navegación fluida. Costo: más trabajo del navegador, carga inicial más pesada y, sin estrategia extra, peor SEO.

React se asocia mucho a CSR (SPAs), pero **no está obligado a vivir solo ahí**: también se usa en SSR con frameworks como Next. En esta materia se lo piensa primero en su versión más simple: React como herramienta para una **interfaz cliente dinámica** que luego dialoga con sistemas cliente-servidor (p. ej. backends en Elixir).

### Arranque con Vite

**Vite** es una herramienta de desarrollo para frontend: crea el proyecto base, levanta un servidor de desarrollo, recarga cambios rápido y genera el build final (optimizado en producción). Es la forma práctica de arrancar una app React sin pelearse con configuración.

```bash
npm create vite@latest mi-app -- --template react
cd mi-app
npm install
npm run dev
```

**Estructura mínima a reconocer:** `index.html`, `src/main.jsx` (punto de entrada) y `src/App.jsx` (componente principal desde donde empieza la UI).

### Primer componente

Un **componente funcional es una función que devuelve JSX**:

```jsx
function App() {
  return <h1>Hola, mundo</h1>
}

export default App
```

### JSX

JSX es una sintaxis que permite escribir una estructura **parecida a HTML** dentro de JavaScript (parece HTML pero no lo es exactamente).

```jsx
function App() {
  return (
    <div>
      <h1>Reserva de vuelos</h1>
      <p>Bienvenidos a Cóndor del Sur</p>
    </div>
  )
}
```

Ideas importantes: siempre se devuelve **una estructura**; se pueden interpolar expresiones con llaves `{}`; se usa **`className`** en lugar de `class`; un componente debe devolver **una única raíz lógica**.

```jsx
function App() {
  const flightCode = "AR1234"
  return <h1>Vuelo {flightCode}</h1>
}
```

### Operadores para renderizar según el estado

- **`&&`** — mostrar algo solo si una condición es verdadera:

  ```jsx
  {seat.available && <button>Reservar</button>}
  ```

- **Ternario `? :`** — elegir entre dos salidas:

  ```jsx
  {confirmed ? <p>Confirmada</p> : <p>Pendiente</p>}
  ```

- **`map`** — transformar listas de datos en listas de elementos (cada elemento necesita una `key`):

  ```jsx
  <ul>
    {seats.map((seat) => (
      <li key={seat.code}>{seat.code}</li>
    ))}
  </ul>
  ```

- **`??` (nullish coalescing)** — valor por defecto si algo es `null` o `undefined`:

  ```jsx
  {passengerName ?? "Sin nombre"}
  ```

### Componentes y composición

Un componente puede usar otros componentes; una UI grande se descompone en piezas chicas (modularizar):

```jsx
function Title() {
  return <h1>Reserva de vuelos</h1>
}

function App() {
  return (
    <div>
      <Title />
      <p>Sistema de reservas</p>
    </div>
  )
}
```

### Props

Las **props** son datos que un componente recibe **desde afuera** (su entrada). El componente no inventa esos datos: los recibe y renderiza en consecuencia.

```jsx
function FlightCard({ code, destination }) {
  return <h2>{code} → {destination}</h2>
}

function App() {
  return <FlightCard code="AR1234" destination="Bariloche" />
}
```

### Estado con `useState`

`useState` permite que un componente mantenga **estado local**.

```jsx
import { useState } from "react"

function Counter() {
  const [count, setCount] = useState(0)

  return (
    <div>
      <p>Count: {count}</p>
      <button onClick={() => setCount(count + 1)}>+1</button>
    </div>
  )
}
```

- `count` es el estado actual,
- `setCount` **pide** actualizar ese estado,
- al cambiar el estado, React **vuelve a renderizar** el componente.

Cómo pensarlo (no como mutación manual del DOM): 1) tengo un estado actual, 2) ocurre un evento, 3) pido un nuevo estado, 4) React recalcula la UI.

### Efectos con `useEffect`

A veces un componente necesita hacer algo **además de renderizar**: pedir datos a una API, suscribirse a algo, loguear, sincronizar con el mundo externo. Para eso está `useEffect`. El **array de dependencias** le dice a React cuándo volver a ejecutar el efecto.

```jsx
import { useEffect, useState } from "react"

function App() {
  const [count, setCount] = useState(0)

  useEffect(() => {
    console.log("el count cambió:", count)
  }, [count])

  return <button onClick={() => setCount(count + 1)}>{count}</button>
}
```

El render describe UI; `useEffect` sirve para **efectos laterales**; no hay que mezclar todo indiscriminadamente.

### Eventos

Un evento dispara lógica; esa lógica puede actualizar estado; si cambia el estado, cambia lo que se ve.

```jsx
function ButtonDemo() {
  function handleClick() {
    console.log("click")
  }
  return <button onClick={handleClick}>Click</button>
}
```

### Render condicional y de listas

```jsx
// condicional (dos formas equivalentes)
function ReservationStatus({ confirmed }) {
  if (confirmed) return <p>Reserva confirmada</p>
  return <p>Reserva pendiente</p>
}

function ReservationStatus({ confirmed }) {
  return <p>{confirmed ? "Reserva confirmada" : "Reserva pendiente"}</p>
}

// listas (renderizar una lista es transformar datos en UI; cada item necesita key)
function SeatList({ seats }) {
  return (
    <ul>
      {seats.map((seat) => (
        <li key={seat.code}>{seat.code}</li>
      ))}
    </ul>
  )
}
```

### Ejemplo integrador: Tic-Tac-Toe

Ejemplo chico (basado en la doc oficial de React) que junta componentes, props, estado, eventos, render según estado, composición e historial de jugadas. Piezas: `Square`, `Board`, `Game` y la función auxiliar `calculateWinner`.

**`Square`** — una celda. Recibe datos por props, no decide su valor ni mantiene estado propio; solo renderiza y dispara un evento:

```jsx
function Square({ value, onClick }) {
  return (
    <button className="square" onClick={onClick}>
      {value}
    </button>
  )
}
```

**`Board`** — el tablero. Decide qué pasa al hacer click: el click **no muta** la UI directamente; se construye un **nuevo array** `nextSquares` y el cambio se delega con `onPlay`:

```jsx
function Board({ xIsNext, squares, onPlay }) {
  function handleClick(index) {
    if (calculateWinner(squares) || squares[index]) return

    const nextSquares = [...squares]
    nextSquares[index] = xIsNext ? "X" : "O"
    onPlay(nextSquares)
  }

  const winner = calculateWinner(squares)
  const status = winner
    ? `Ganador: ${winner}`
    : `Siguiente jugador: ${xIsNext ? "X" : "O"}`

  return (
    <>
      <div className="status">{status}</div>
      <div className="board-row">
        <Square value={squares[0]} onClick={() => handleClick(0)} />
        <Square value={squares[1]} onClick={() => handleClick(1)} />
        <Square value={squares[2]} onClick={() => handleClick(2)} />
      </div>
      {/* filas 4-6 y 7-9 idénticas con índices 3..5 y 6..8 */}
    </>
  )
}
```

**`Game`** — mantiene el **estado principal** (más arriba que `Board`): el historial de tableros y el movimiento actual. Renderiza la UI en función del estado actual y permite "viajar" a una jugada previa:

```jsx
import { useState } from "react"

export default function Game() {
  const [history, setHistory] = useState([Array(9).fill(null)])
  const [currentMove, setCurrentMove] = useState(0)

  const xIsNext = currentMove % 2 === 0
  const currentSquares = history[currentMove]

  function handlePlay(nextSquares) {
    const nextHistory = [...history.slice(0, currentMove + 1), nextSquares]
    setHistory(nextHistory)
    setCurrentMove(nextHistory.length - 1)
  }

  function jumpTo(nextMove) {
    setCurrentMove(nextMove)
  }

  const moves = history.map((_, move) => {
    const description = move === 0 ? "Ir al inicio" : `Ir al movimiento #${move}`
    return (
      <li key={move}>
        <button onClick={() => jumpTo(move)}>{description}</button>
      </li>
    )
  })

  return (
    <div className="game">
      <div className="game-board">
        <Board xIsNext={xIsNext} squares={currentSquares} onPlay={handlePlay} />
      </div>
      <div className="game-info">
        <ol>{moves}</ol>
      </div>
    </div>
  )
}
```

**`calculateWinner`** — **función pura** que resuelve algo del dominio (separar lógica de negocio del render):

```jsx
function calculateWinner(squares) {
  const lines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
  ]

  for (const [a, b, c] of lines) {
    if (squares[a] && squares[a] === squares[b] && squares[a] === squares[c]) {
      return squares[a]
    }
  }
  return null
}
```

**Modelo mental de la clase:** componentes funcionales + props + estado + efectos + **render según estado actual**. Con eso alcanza para leer, modificar y construir una UI básica.

---

## 7. React práctico (mini app con router, fetch y useMemo)

App de ejemplo: **Holocron Atlas**, una mini UI que consume datos de Star Wars desde `swapi.info`. Sirve para practicar `useState`, `useEffect`, **router básico**, `useMemo` y `fetch`. Tiene cuatro vistas: Home, lista de personajes, detalle de personaje (según `id` de la URL) y lista de naves con un formulario de filtros.

### Setup

```bash
npm create vite@latest react-swapi -- --template react
cd react-swapi
npm install
npm install react-router-dom
npm run dev
```

Estructura: `index.html`, `src/main.jsx` (entrada), `src/App.jsx` (componente principal), `src/pages/...` (una pantalla por archivo).

### Router

En una app React no se quiere una sola pantalla gigante: se navega entre vistas (`/`, `/people`, `/people/:id`, `/starships`). Para eso, `react-router-dom`. Se envuelve la app en `<BrowserRouter>`:

```jsx
// src/main.jsx
import React from "react"
import ReactDOM from "react-dom/client"
import { BrowserRouter } from "react-router-dom"
import App from "./App"
import "./index.css"

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>
)
```

```jsx
// src/App.jsx (rutas principales)
import { Link, Route, Routes } from "react-router-dom"
import HomePage from "./pages/HomePage"
import PeoplePage from "./pages/PeoplePage"
import PersonDetailPage from "./pages/PersonDetailPage"
import StarshipsPage from "./pages/StarshipsPage"

export default function App() {
  return (
    <div className="app-shell">
      <header className="site-header">
        <nav className="nav">
          <Link to="/">Home</Link>
          <Link to="/people">Characters</Link>
          <Link to="/starships">Fleet</Link>
        </nav>
      </header>

      <main className="container main-content">
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/people" element={<PeoplePage />} />
          <Route path="/people/:id" element={<PersonDetailPage />} />
          <Route path="/starships" element={<StarshipsPage />} />
        </Routes>
      </main>
    </div>
  )
}
```

Piezas del router: **`Link`** navega entre rutas; **`Routes`** agrupa el conjunto de rutas; **`Route`** define qué componente mostrar para cada `path`; **`:id`** define un **parámetro dinámico** de ruta.

### `fetch`

`fetch` es la API nativa del navegador para hacer requests HTTP:

```jsx
const response = await fetch("https://swapi.info/api/people")
const data = await response.json()
```

### Patrón de carga de datos: `data` / `loading` / `error`

No alcanza con guardar los datos: también hay que **modelar qué está pasando con la request**. Por eso suele haber tres estados. El `useEffect` corre al montar el componente (dependencias `[]`) y la UI cambia según si está cargando, si hubo error o si llegaron los datos.

```jsx
// src/pages/PeoplePage.jsx
import { useEffect, useState } from "react"
import { Link } from "react-router-dom"

export default function PeoplePage() {
  const [people, setPeople] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    async function loadPeople() {
      try {
        setLoading(true)
        setError(null)

        const response = await fetch("https://swapi.info/api/people")
        if (!response.ok) throw new Error("Unable to retrieve archive records")

        const data = await response.json()
        setPeople(data)
      } catch (err) {
        setError(err.message)
      } finally {
        setLoading(false)
      }
    }

    loadPeople()
  }, [])

  if (loading) return <p className="muted">Syncing character archive...</p>
  if (error) return <p className="error-text">Error: {error}</p>

  return (
    <div className="grid">
      {people.map((person) => {
        const id = person.url.split("/").filter(Boolean).pop()
        return (
          <article key={person.url} className="card person-card">
            <h3>{person.name}</h3>
            <p className="muted">Birth year: {person.birth_year}</p>
            <Link className="button" to={`/people/${id}`}>Open dossier</Link>
          </article>
        )
      })}
    </div>
  )
}
```

### Parámetros de ruta: `useParams`

Para leer el `id` de una ruta como `/people/1` se usa `useParams()`. El efecto **depende de `id`** (`[id]`): si la ruta cambia, el componente vuelve a pedir el recurso correcto. `value ?? "Unknown"` permite renderizar datos incompletos sin romper la UI.

```jsx
// src/pages/PersonDetailPage.jsx
import { useEffect, useState } from "react"
import { Link, useParams } from "react-router-dom"

export default function PersonDetailPage() {
  const { id } = useParams()

  const [person, setPerson] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    async function loadPerson() {
      try {
        setLoading(true)
        setError(null)

        const response = await fetch(`https://swapi.info/api/people/${id}`)
        if (!response.ok) throw new Error("Unable to retrieve character dossier")

        const data = await response.json()
        setPerson(data)
      } catch (err) {
        setError(err.message)
      } finally {
        setLoading(false)
      }
    }

    loadPerson()
  }, [id])

  if (loading) return <p className="muted">Opening dossier...</p>
  if (error) return <p className="error-text">Error: {error}</p>
  if (!person) return <p className="muted">Dossier not found.</p>

  return (
    <article className="card detail-card">
      <h2>{person.name}</h2>
      <p>Height: {person.height ?? "Unknown"}</p>
      <p>Mass: {person.mass ?? "Unknown"}</p>
      <p>Birth year: {person.birth_year ?? "Unknown"}</p>
    </article>
  )
}
```

### Formularios controlados (controlled components)

En React un input suele manejarse como **controlled component**: el valor del input **vive en el estado**, el input muestra ese valor y, al cambiar, actualiza el estado. Así la UI y el estado quedan **sincronizados** y el estado del componente es la **única fuente de verdad** (no hay un valor escondido "dentro del input" distinto del de la lógica).

```jsx
const [search, setSearch] = useState("")

<input value={search} onChange={(e) => setSearch(e.target.value)} />
```

Flujo: 1) el usuario escribe → 2) se dispara `onChange` → 3) se actualiza `search` → 4) React re-renderiza → 5) el input muestra el nuevo valor. Un botón de **reset** solo necesita volver el estado a sus valores iniciales y los inputs se actualizan solos.

### Valores derivados: `useMemo`

`useMemo` **memoiza un valor derivado** del estado o de props, y lo **recalcula solo cuando cambian sus dependencias**. No reemplaza a `useState` ni a `useEffect`.

```jsx
const filteredItems = useMemo(() => {
  return items.filter(...)
}, [items, search])
```

La idea importante: la lista que se muestra **no** es la original, es una **vista derivada** construida a partir de los datos + el estado del formulario. **No se "filtra el DOM"** ni se esconden/muestran tarjetas a mano: se **recalcula qué lista debería existir** según el estado actual.

### Página de naves: dos tipos de estado + `useMemo`

`StarshipsPage` usa `useState` para dos cosas distintas:

1. **Estado de datos** (lo que vino de la API): `starships`, `loading`, `error`.
2. **Estado del formulario** (lo que el usuario eligió): `search`, `minCrew`, `sortBy`.

La lista final (`filteredStarships`) se deriva con `useMemo` a partir de ambos. Cuando cambia una dependencia, React re-renderiza, `useMemo` detecta el cambio y recalcula la lista.

```jsx
// src/pages/StarshipsPage.jsx (núcleo)
import { useEffect, useMemo, useState } from "react"

export default function StarshipsPage() {
  const [starships, setStarships] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const [search, setSearch] = useState("")
  const [minCrew, setMinCrew] = useState("")
  const [sortBy, setSortBy] = useState("name")

  useEffect(() => {
    async function loadStarships() {
      try {
        setLoading(true)
        setError(null)
        const response = await fetch("https://swapi.info/api/starships")
        if (!response.ok) throw new Error("Unable to retrieve fleet registry")
        const data = await response.json()
        setStarships(data)
      } catch (err) {
        setError(err.message)
      } finally {
        setLoading(false)
      }
    }
    loadStarships()
  }, [])

  const filteredStarships = useMemo(() => {
    const normalizedSearch = search.trim().toLowerCase()

    const result = starships.filter((ship) => {
      const matchesSearch =
        normalizedSearch === "" ||
        ship.name.toLowerCase().includes(normalizedSearch) ||
        ship.model.toLowerCase().includes(normalizedSearch)

      const crewNumber = parseInt(String(ship.crew).replace(/,/g, ""), 10)
      const minCrewNumber = parseInt(minCrew, 10)
      const matchesCrew =
        minCrew === "" ||
        (!Number.isNaN(crewNumber) && crewNumber >= minCrewNumber)

      return matchesSearch && matchesCrew
    })

    result.sort((a, b) => {
      if (sortBy === "crew") {
        const crewA = parseInt(String(a.crew).replace(/,/g, ""), 10) || 0
        const crewB = parseInt(String(b.crew).replace(/,/g, ""), 10) || 0
        return crewA - crewB
      }
      return a.name.localeCompare(b.name)
    })

    return result
  }, [starships, search, minCrew, sortBy])

  function handleReset() {
    setSearch("")
    setMinCrew("")
    setSortBy("name")
  }

  // ... loading / error guards ...

  return (
    <section className="page-stack">
      <form className="card filters" onSubmit={(e) => e.preventDefault()}>
        <input type="text" value={search}
               onChange={(e) => setSearch(e.target.value)} />

        <input type="number" min="0" value={minCrew}
               onChange={(e) => setMinCrew(e.target.value)} />

        <select value={sortBy} onChange={(e) => setSortBy(e.target.value)}>
          <option value="name">Name</option>
          <option value="crew">Crew</option>
        </select>

        <button type="button" onClick={handleReset}>Reset filters</button>
      </form>

      <div className="grid">
        {filteredStarships.map((ship) => (
          <article key={ship.url} className="card">
            <h3>{ship.name}</h3>
            <p className="muted">{ship.model}</p>
          </article>
        ))}
      </div>
    </section>
  )
}
```

Qué hace el `useMemo` por dentro: **normaliza** el texto de búsqueda (`trim().toLowerCase()`), **filtra** por nombre o modelo (si no hay búsqueda, pasa todo), **filtra** por tripulación mínima (convirtiendo los valores a números comparables) y **ordena** el resultado (por `crew` o por `name` con `localeCompare`). El formulario no modifica la lista directamente: solo cambia `search`/`minCrew`/`sortBy`, y de ahí se recalcula la vista.

### Resumen conceptual de React práctico

- **Router** → divide la aplicación en pantallas.
- **`useState`** → estado local.
- **`useEffect`** → efectos laterales (p. ej. pedir datos).
- **`fetch`** → requests HTTP.
- **`useMemo`** → valores derivados del estado.
- **Render según estado actual** → la interfaz no se manipula manualmente, se **recalcula** a partir del estado.

Esta base sirve para seguir con componentes más chicos, formularios más complejos, requests a un backend propio e integración con APIs hechas por uno mismo (cierre del puente React ↔ Elixir).

---

> **Nota:** El TP final de la cátedra (tema "Sistema de reserva de asientos en vuelos", grupal de 3–4 personas) integra estos contenidos (un backend cliente-servidor en Elixir/OTP + una UI en React). Este resumen cubre la teoría de base; el enunciado puntual del TP y sus notas anexadas no estaban incluidos en las páginas resumidas.
