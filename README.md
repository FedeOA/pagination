# Guía completa de paginación en APIs (Spring Boot + JPA)

Este repositorio utiliza `Product` como ejemplo para estudiar las alternativas de paginación en APIs desarrolladas con **Java 17+, Spring Boot 3, Spring Data JPA y Hibernate 6**.

El objetivo es comprender cómo funcionan `offset/page`, `slice`, `keyset (seek)` y `cursor token`, analizar sus compromisos y elegir el enfoque adecuado según los requisitos de navegación, volumen de datos, rendimiento y concurrencia.

> **Alcance:** los ejemplos SQL y HTTP de esta guía son conceptuales, salvo el endpoint `GET /api/products` identificado como existente. La existencia de un skill no implica que su endpoint ya esté implementado.

## Contenido

- [Objetivo de la paginación](#objetivo-de-la-paginación)
- [Cómo se relacionan las estrategias](#cómo-se-relacionan-las-estrategias)
- [Conceptos comunes](#conceptos-comunes)
- [1. Offset / Page](#1-offset--page)
- [2. Slice](#2-slice)
- [3. Keyset / Seek](#3-keyset--seek)
- [4. Cursor Token](#4-cursor-token)
- [Comportamiento ante cambios concurrentes](#comportamiento-ante-cambios-concurrentes)
- [Comparativa rápida](#comparativa-rápida)
- [Cómo decidir](#cómo-decidir)
- [Índices recomendados](#índices-recomendados)
- [Errores frecuentes](#errores-frecuentes)
- [Ejemplos de requests](#ejemplos-de-requests)
- [Skills del repositorio](#skills-del-repositorio)
- [Referencias oficiales](#referencias-oficiales)

---

## Objetivo de la paginación

Paginar evita recuperar todo un conjunto de resultados en una sola petición. Permite controlar el tamaño de la respuesta y, con una estrategia apropiada, reducir el trabajo de la base de datos. Esto suele mejorar el consumo de memoria, el ancho de banda, el tiempo de respuesta y la experiencia de navegación.

La paginación **no garantiza por sí sola** una vista consistente de los datos cuando estos cambian entre peticiones.

## Cómo se relacionan las estrategias

Es útil distinguir tres niveles:

| Nivel | Conceptos | Qué resuelven |
|---|---|---|
| Acceso a datos | **Offset**, **Keyset / Seek** | Cómo encontrar los próximos registros en SQL |
| Abstracción de Spring Data | **Page**, **Slice**, **Window** | Qué metadatos y mecanismos de navegación ofrece el repositorio |
| Contrato de API | **page/size**, **valores de posición**, **cursor token** | Qué envía y recibe el cliente |

- `Page<T>` suele utilizar Offset y proporciona totales (`totalElements`, `totalPages`).
- `Slice<T>` con `PageRequest` utiliza Offset, pero evita consultar el total global.
- `Window<T>` puede utilizar scrolling basado en Offset **o** en Keyset (`KeysetScrollPosition`).
- Un **cursor token** representa una posición de navegación; en este proyecto se utiliza sobre **Keyset**. Un cursor no garantiza por sí mismo que la consulta sea eficiente: también existen cursores que codifican offsets.

Por lo tanto, los cuatro enfoques de este repositorio no son cuatro algoritmos SQL independientes.

## Conceptos comunes

### Ordenamiento determinista

Siempre ordenar mediante una secuencia que identifique de forma inequívoca la posición de cada fila. Ejemplo:

```sql
ORDER BY created_at DESC, id DESC
```

Si `created_at` se repite, `id` actúa como desempate único. Un orden determinista evita ambigüedades entre empates, **pero no evita** los desplazamientos causados por inserciones o eliminaciones cuando se usa Offset.

Preferir columnas de ordenamiento **no nulas**, indexables y, para Keyset, estables a lo largo de la navegación. Si se modifica una columna de ordenamiento, un registro puede cambiar de posición entre solicitudes.

### Parámetros y errores

- **Page / Slice:** recibir `page` y `size`. Establecer explícitamente si la API usa base **0** o **1**. Validar `page >= base` y `1 <= size <= maxSize`.
- **Keyset / Cursor Token:** recibir `limit` y una posición opcional (`lastCreatedAt` + `lastId` o `cursor`). Validar `1 <= limit <= maxLimit`.
- Normalizar parámetros omitidos usando valores predeterminados definidos en la aplicación.
- Reutilizar `InvalidPaginationException` para parámetros numéricos inválidos e `InvalidCursorException` para tokens inválidos; delegar el mapeo HTTP al manejador global del proyecto.
- Si se acepta un sort externo, utilizar una **allowlist** e incorporar siempre el desempate único.

### DTOs y asociaciones JPA

- No exponer entidades JPA en la respuesta HTTP.
- Para DTOs planos, considerar proyección directa a record/interface cuando sea compatible con la consulta.
- Para transformación adicional, recuperar entidades y utilizar MapStruct.
- Para relaciones `ToOne` necesarias en el mapeo de entidades, evaluar `@EntityGraph`.
- Evitar `JOIN FETCH` de **colecciones** junto con paginación; según la consulta y la versión de Hibernate, puede provocar paginación en memoria. Evaluar batch fetching o consultas en dos fases.
- En Hibernate 6, se recomienda detectar el problema mediante:

```properties
spring.jpa.properties.hibernate.query.fail_on_pagination_over_collection_fetch=true
```

### Concurrencia y snapshot

En una API REST, cada página suele solicitarse mediante una petición HTTP independiente. Ninguno de estos enfoques garantiza automáticamente que todas las peticiones observen el mismo estado de la base de datos.

`@Transactional(readOnly = true)` por petición no crea un snapshot compartido entre peticiones; un nivel de aislamiento como `REPEATABLE_READ` solo puede mantener una vista consistente **dentro de una misma transacción**, conforme a las reglas del motor.

---

## 1. Offset / Page

### En qué consiste

El cliente indica un número de página y su tamaño. Para una API **base 0**:

```text
offset = page * size
limit  = size
```

Para una API **base 1**, antes de consultar:

```text
offset = (page - 1) * size
```

En Spring Data JPA, `PageRequest.of(...)` siempre recibe el número de página **base 0**. Si la API expone base 1, también debe convertir de regreso el número que se devuelve en el DTO de respuesta.

### Mecanismo

```sql
SELECT ...
FROM products
ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 2000;
```

En Spring Data:

```java
Page<Product> findByStatus(Status status, Pageable pageable);
```

`Page<T>` puede ejecutar una consulta adicional de `COUNT(*)` para conocer `totalElements` y `totalPages` (Spring Data puede omitirla en ciertos casos).

### Ventajas

- Fácil de implementar y consumir.
- Integración directa con `Pageable`, `PageRequest` y `Page<T>`.
- Permite saltar a una página numerada.
- Conveniente cuando el cliente necesita totales.

### Desventajas

- El trabajo de la base de datos puede crecer con offsets elevados.
- Inserciones/eliminaciones entre peticiones pueden ocasionar duplicados u omisiones.
- La consulta de conteo puede ser costosa para ciertos filtros, joins o volúmenes de datos.

### Cuándo usarlo

Backoffice, tablas paginadas con números de página, reportes interactivos que requieren totales y listados de volumen moderado o navegación poco profunda.

---

## 2. Slice

### En qué consiste

`Slice<T>` es una **abstracción de Spring Data**, no una estrategia SQL distinta. Con `PageRequest`, usa Offset como `Page<T>`, pero no necesita calcular los totales globales.

### Mecanismo

En una consulta ordinaria, solicita hasta `size + 1` registros para determinar si existe una página siguiente:

```sql
SELECT ...
FROM products
ORDER BY created_at DESC, id DESC
LIMIT 21 OFFSET 2000;
```

Si se solicitaron 20 elementos y aparece el registro 21, `hasNext = true`; ese elemento adicional no se incluye en `content`.

En Spring Data:

```java
Slice<Product> findByStatus(Status status, Pageable pageable);
```

### Ventajas

- No necesita `COUNT(*)` para obtener totales.
- Permite saber si hay otra página mediante `hasNext()`.
- Útil para interfaces con «Cargar más» cuando el costo del Offset es aceptable.

### Desventajas

- No proporciona `totalElements` ni `totalPages`.
- **Sigue teniendo los problemas de Offset:** páginas profundas y desplazamientos ante inserciones/eliminaciones.

### Cuándo usarlo

Listados sin totales globales, resultados poco profundos y UIs que solo necesitan avanzar o retroceder, siempre que el Offset siga siendo razonable.

---

## 3. Keyset / Seek

### En qué consiste

Keyset recupera los siguientes resultados a partir de los **valores de ordenamiento del último registro devuelto**, en lugar de calcular cuántas filas debe saltar.

### Mecanismo

Si el orden es `created_at DESC, id DESC`, la primera consulta puede ser:

```sql
SELECT ...
FROM products
ORDER BY created_at DESC, id DESC
LIMIT 21;
```

Para continuar desde una posición conocida:

```sql
SELECT ...
FROM products
WHERE created_at < :lastCreatedAt
   OR (created_at = :lastCreatedAt AND id < :lastId)
ORDER BY created_at DESC, id DESC
LIMIT 21;
```

Aquí se supone `limit = 20` y se recupera **uno extra** para calcular `hasNext`. La siguiente posición se construye con el último registro **incluido** entre los 20 devueltos, nunca con el registro adicional.

- La primera petición no necesita posición.
- La posición debe incluir **todas** las claves necesarias para continuar y conservar los tipos/precisión de datos.
- El ejemplo requiere `created_at` e `id` no nulos. Para otros órdenes (ASC, direcciones mixtas o más columnas), hay que adaptar el predicado.
- Los filtros de negocio y autorizaciones se vuelven a aplicar en cada consulta.

En Spring Data JPA puede implementarse manualmente con JPQL/Criteria o mediante `Window<T>` y `KeysetScrollPosition` cuando la consulta es compatible. El scrolling nativo no está disponible directamente para métodos `@Query` con JPQL escrito como cadena.

### Ventajas

- Evita el trabajo acumulado de offsets elevados cuando existen índices apropiados.
- Mitiga duplicados y omisiones causados por cambios en posiciones anteriores al cursor.
- Adecuado para navegación secuencial y muchos registros.

### Desventajas

- No permite saltar directamente a una página numerada arbitraria sin disponer de una posición previa.
- Exige orden y predicado correctos, tipos precisos e índices apropiados.
- No garantiza un snapshot fijo; inserciones nuevas por delante del cursor pueden no aparecer, y modificaciones del campo de orden pueden producir anomalías.

### Cuándo usarlo

Scroll infinito, historiales extensos, grandes volúmenes de datos, procesamiento secuencial y APIs sensibles a la latencia de páginas profundas.

---

## 4. Cursor Token

### En qué consiste

En este proyecto, Cursor Token es una **capa de contrato HTTP sobre Keyset**. El cliente recibe `nextCursor`, lo devuelve sin interpretarlo y el servidor recupera la posición de navegación.

Un cursor podría ser también un offset codificado, pero **esa no es la implementación que promueven los skills de este repositorio**.

### Mecanismo

1. El servidor aplica la consulta Keyset inicial y devuelve `content`, `hasNext` y `nextCursor`.
2. Si `hasNext = true`, el cliente envía el cursor en la siguiente petición.
3. El servidor valida el token, reconstruye la posición y ejecuta la siguiente consulta Keyset con los mismos filtros y autorizaciones.
4. Cuando no hay más resultados, devuelve `nextCursor = null`.

El token puede contener internamente versión, última posición, huella de filtros/orden, contexto de autorización y, opcionalmente, datos de expiración.

### Seguridad del token

- **Base64Url es codificación, no cifrado.** El cliente puede decodificar un payload JSON.
- **HMAC** protege integridad y autenticidad del token, **no** confidencialidad.
- Si realmente se deben ocultar los valores internos, utilizar cifrado autenticado (p. ej. AES-GCM) o un identificador aleatorio almacenado del lado del servidor.
- Vincular el token a filtros, ordenamiento y contexto de acceso, para evitar reutilizarlo en una consulta diferente.
- Validar versión, estructura, firma/cifrado, longitud, posición y expiración cuando se configure.
- Nunca considerar el token un sustituto de autorización: volver a aplicar filtros de seguridad en cada petición.
- Obtener claves de secretos/configuración segura, no hardcodearlas ni registrar tokens completos.

### Ventajas

- El consumidor no necesita conocer cómo se construye la posición Keyset.
- Permite evolucionar/versionar el contrato del cursor.
- Es adecuado para APIs públicas y móviles.
- Mantiene las ventajas de rendimiento de Keyset cuando se implementa sobre Keyset real.

### Desventajas

- Requiere codec, validación y manejo de tokens inválidos.
- Puede requerir gestión de claves, rotación y expiración.
- No aporta una mejora de rendimiento SQL adicional respecto de Keyset con la misma consulta.

### Cuándo usarlo

APIs públicas, aplicaciones móviles y contratos HTTP donde se prefiera que la representación interna de la posición no sea parte del contrato de consumo.

---

## Comportamiento ante cambios concurrentes

| Situación entre dos peticiones | Offset con `Page` o `Slice` | Keyset y Cursor sobre Keyset |
|---|---|---|
| Inserción antes de la posición ya visitada | Puede duplicar registros | No desplaza los resultados posteriores |
| Eliminación antes de la posición ya visitada | Puede omitir registros | No desplaza los resultados posteriores |
| Inserción después de la posición de Keyset | Puede cambiar la composición de páginas | Puede aparecer en una ventana posterior |
| Modificación de un campo del orden | Puede duplicar u omitir | También puede duplicar u omitir |
| Snapshot consistente entre requests | No, por defecto | No, por defecto |

**Importante:** si se elimina un registro todavía no leído, Keyset no puede devolverlo. Su ventaja es evitar errores de **desplazamiento**, no conservar una copia histórica de todas las filas.

Si el caso exige una foto exacta de un instante (por ejemplo, una exportación auditable), evaluar una transacción con snapshot único para una operación acotada, una materialización de IDs o un mecanismo específico de snapshot/versionado, de acuerdo con el volumen y el motor de base de datos.

## Comparativa rápida

| Enfoque | Consultas profundas | Totales globales | Saltar a página N | Riesgo por desplazamientos | Complejidad |
|---|---|---|---|---|---|
| Offset + `Page` | Puede degradarse | Sí | Sí | Alto | Baja |
| Offset + `Slice` | Puede degradarse | No | Sí | Alto | Baja |
| Keyset / Seek | Eficiente con índice apropiado | No, habitualmente | No directamente | Bajo | Media |
| Cursor Token sobre Keyset | Igual que Keyset | No, habitualmente | No directamente | Bajo | Media/alta |

*«Bajo» no significa consistencia absoluta: se mantienen las limitaciones descritas en la sección de concurrencia.*

## Cómo decidir

1. **¿Necesitás `totalElements` y `totalPages` o saltar a una página exacta?** Usá Offset + `Page`.
2. **¿Solo necesitás `hasNext` y las páginas no son demasiado profundas?** Usá Offset + `Slice`.
3. **¿Necesitás recorrer muchos registros sin pagar offsets crecientes?** Usá Keyset.
4. **¿Además querés encapsular la posición de navegación para una API pública?** Usá Cursor Token sobre Keyset.

No hay que migrar de Offset a Keyset solamente porque una tabla sea grande: importa la profundidad de navegación, la selectividad de filtros, los índices y la latencia observada. Analizar con datos representativos.

## Índices recomendados

El índice óptimo depende de los predicados y del `ORDER BY`.

Para ordenar sin filtros:

```sql
CREATE INDEX idx_products_created_id
ON products (created_at DESC, id DESC);
```

Para filtrar por una columna en la **misma tabla**:

```sql
CREATE INDEX idx_products_status_created_id
ON products (status, created_at DESC, id DESC);
```

Si `category_id` existe directamente en `products`, puede ser candidato:

```sql
CREATE INDEX idx_products_category_created_id
ON products (category_id, created_at DESC, id DESC);
```

Si la categoría se relaciona mediante una tabla intermedia, no se puede crear un único índice que abarque columnas de dos tablas: hay que estudiar los índices de ambas tablas y el plan del JOIN.

- Un filtro `LIKE '%texto%'` normalmente no aprovecha un índice B-tree tradicional para ubicar directamente el prefijo; evaluar búsqueda de texto especializada si hace falta.
- Un índice es una **hipótesis de optimización**, no una garantía: validar con `EXPLAIN` / `EXPLAIN ANALYZE` según el motor.
- No aplicar reglas de índices aisladas del volumen, cardinalidad, filtros y orden real.

## Errores frecuentes

- Confundir `Slice` con una estrategia que no utiliza Offset.
- Pensar que Cursor Token es necesariamente Keyset, o que un token codificado ya está cifrado.
- Dejar un `ORDER BY` sin desempate único.
- Permitir sort libre sin allowlist o cambiar filtros/orden a mitad de una navegación Keyset.
- Usar columnas de ordenamiento nulas o mutables sin tratar sus consecuencias.
- Usar un cursor de fecha con pérdida de precisión.
- Calcular `nextCursor` desde la fila adicional de `limit + 1` en vez de la última fila devuelta.
- Aplicar `JOIN FETCH` de colecciones sobre consultas limitadas sin revisar las consecuencias.
- Suponer que `@Transactional(readOnly = true)` entre requests garantiza el mismo snapshot.
- Olvidar convertir los números de página entre base pública 1 y base interna 0.
- Suponer que Keyset resuelve consultas lentas causadas por filtros no selectivos, joins o índices deficientes.

## Ejemplos de requests

Los endpoints `/slice`, `/keyset` y `/cursor` de abajo son **conceptuales**; no se afirma que existan actualmente.

### Offset / Page (endpoint existente del proyecto)

`GET /api/products`

Parámetros indicados para el endpoint actual:

- `name`
- `minPrice`
- `maxPrice`
- `categoryId`
- `createdAtFrom`
- `createdAtTo`
- `page`
- `size`

Ejemplo (base 0):

```http
GET /api/products?page=0&size=20&name=pro&minPrice=10&maxPrice=200
```

### Slice (ejemplo conceptual)

```http
GET /api/products/slice?page=0&size=20
GET /api/products/slice?page=1&size=20
```

### Keyset (ejemplo conceptual)

Se usa `limit` para coincidir con el contrato de los skills de Keyset y Cursor:

```http
GET /api/products/keyset?limit=20&name=pro
GET /api/products/keyset?limit=20&name=pro&lastCreatedAt=2026-10-25T10%3A00%3A00Z&lastId=123
```

`lastCreatedAt` debe transmitirse con la zona horaria y precisión compatible con la columna y con el tipo Java utilizado. El valor anterior es ilustrativo.

### Cursor Token (ejemplo conceptual)

```http
GET /api/products/cursor?limit=20&name=pro
GET /api/products/cursor?limit=20&name=pro&cursor=<TOKEN_URL_SAFE>
```

`<TOKEN_URL_SAFE>` representa un token real emitido por el servidor; no es un token válido literal. El cliente debe reenviarlo sin interpretarlo. Los filtros deben seguir siendo compatibles con los vinculados al token.

## Skills del repositorio

Cada skill es un **generador interactivo** de código Java, no una implementación productiva ya integrada. Su estructura prevista es:

| Skill | Responsabilidad principal |
|---|---|
| `pagination-offset-jpa` | `Page<T>`, totales y numeración de páginas |
| `pagination-slice-jpa` | `Slice<T>`, sin totales globales, con Offset |
| `pagination-keyset-jpa` | Seek por valores tipados, sin Offset |
| `pagination-cursor-token-jpa` | Keyset interno y token con validación |

Reglas comunes: validación de parámetros, respuesta con DTOs, ordenamiento determinista, índices coherentes, manejo seguro de asociaciones, excepciones reutilizables y advertencias sobre concurrencia. Los skills no deben duplicar componentes compartidos existentes ni generar código que mezcle proyección directa con MapStruct innecesariamente.

## Referencias oficiales

- [Spring Data JPA — Query Methods / Scrolling](https://docs.spring.io/spring-data/jpa/reference/jpa/query-methods.html)
- [Spring Data — Paging, Slice y Window](https://docs.spring.io/spring-data/commons/reference/repositories/query-methods-details.html)
- [Spring Data JPA — Projections](https://docs.spring.io/spring-data/jpa/reference/repositories/projections.html)
- [Hibernate ORM — Documentation](https://hibernate.org/orm/documentation/)

---

## Recomendación final

Comenzá por el contrato que necesita el cliente. **`Page`** cuando necesitás totales y navegación numerada; **`Slice`** cuando solo importa avanzar sin calcular totales; **Keyset** cuando el recorrido profundo o la estabilidad frente a desplazamientos lo justifican; y **Cursor Token sobre Keyset** cuando querés encapsular esa posición para consumidores externos.

La estrategia elegida debe validarse con consultas, índices y datos representativos. Ninguna reemplaza el análisis de consistencia cuando la aplicación requiere observar una vista exacta del conjunto de resultados.
