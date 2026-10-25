---
name: pagination-keyset-jpa
description: "Generador interactivo de paginación Keyset/Seek en Spring Boot 3 y JPA con posición tipada, DTO record, MapStruct opcional y respuesta propia. Usar para navegar grandes listados con orden estable sin OFFSET ni COUNT."
---

# Pagination Keyset JPA

## Alcance
Generar código Java 17+ para Spring Boot 3 / Spring Data JPA / Hibernate 6. Navegación **hacia adelante** mediante Keyset/Seek: la próxima consulta empieza **después de la última clave entregada**. Implementación predeterminada mediante JPQL/Criteria + `List<Entity>` limitada; opcionalmente `Window<T>` + `KeysetScrollPosition` cuando resulte compatible. Nunca insertar OFFSET ni usar `Page<T>` para simular Keyset. Sin controllers, tests ni documentación de API salvo solicitud.

## Flujo interactivo
Preguntar **UNA A UNA** los datos no resueltos; esperar respuesta:
1. Entidad, nombre y tipo real de ID; comprobar que la clave de desempate pueda ordenarse/compararse en la BD.
2. Campos del DTO, asociaciones `ToOne`/`ToMany` y mapeo (proyección directa o entidad + MapStruct).
3. Filtros de negocio y tipos; indicar si serán idénticos durante la navegación.
4. Orden **estable** (campos, tipos, dirección ASC/DESC) y desempate único (normalmente ID). Confirmar que los valores de ordenamiento sean no nulos; preferir propiedades inmutables.
5. Formato de posición de entrada (ej. `lastCreatedAt`, `lastId`), `defaultLimit`, `maxLimit` y si se prefiere Keyset manual o soporte `Window` nativo.
6. Paquete base y componentes compartidos existentes.
Resumir y confirmar. Elegir implementación manual cuando la consulta `@Query` o los filtros impidan usar el scrolling nativo; no imponer implementación nativa sin verificar versión/capacidades.

## Archivos a generar
- `<Entity>Dto.java` (record).
- `<Entity>KeysetPosition.java` (record tipado, salvo reutilización válida).
- `KeysetPageResponse.java` (record genérico, reutilizable si el contrato coincide).
- `<Entity>Repository.java` y `<Entity>Service.java`.
- `<Entity>Mapper.java` **solo** cuando se recuperen entidades y se transformen mediante MapStruct.
- `InvalidPaginationException.java` y/o `InvalidKeysetPositionException.java` **solo** si no existen equivalentes.

## Reglas obligatorias
- **Orden**: total y determinista; ejemplo `createdAt DESC, id DESC`. Agregar desempate único. Si hay N columnas de orden, la posición incluye todas las necesarias; generar predicado lexicográfico correcto con la dirección propia de cada columna. Para `DESC` usar `<`, para `ASC` usar `>` (en avance). Con direcciones mixtas construir la disyunción lexicográfica, no copiar a ciegas el ejemplo DESC.
- **Tipos**: utilizar los tipos Java reales de sort e ID (`Instant`, `LocalDateTime`, `Long`, `UUID`, etc.). Verificar que comparaciones e índices sean compatibles con la columna/dialecto; no asumir que todo tipo, en particular un UUID almacenado de una forma específica, admite las comparaciones JPQL esperadas.
- **Nulos**: por defecto exigir claves de orden no nulas y desempate no nulo. Si el modelo admite NULL, resolver explícitamente orden de NULL y predicados SQL; no usar la plantilla simple sin adaptarla. Validar posiciones completas; `null` en toda la posición significa primera ventana, cursor parcialmente nulo es inválido.
- **Estabilidad**: preferir campos que no cambien (ej. `createdAt`); si cambia un campo de orden, puede haber duplicados/omisiones. Mantener los mismos filtros y orden entre ventanas. Inserts posteriores a la posición pueden aparecer; Keyset **no** proporciona snapshot consistente entre peticiones.
- **Consulta**: repositorio manual retorna `List<Entity>` o proyección. Separar consulta de primera ventana y de continuación para simplificar predicados, especialmente con parámetros nulos. `@Query` con `List` + `Pageable` es válido para limitar, pero siempre pasar **`PageRequest.of(0, effectiveLimit + 1)`**: prohibido `PageRequest.of(n > 0, ...)` y `COUNT(*)`.
- **Ventana**: recuperar como máximo `limit + 1`, calcular `hasNext = rows.size() > limit`, devolver los primeros `limit`. La siguiente posición proviene del **último elemento efectivamente devuelto**; jamás de la fila extra. Si no hay siguiente ventana, devolver posición siguiente nula. `size = content.size()` (elementos entregados).
- **Validación**: `defaultLimit >= 1`, `maxLimit >= defaultLimit`, `maxLimit < Integer.MAX_VALUE` para permitir `+1`. Parámetro null → `defaultLimit`; valores inválidos → excepción propia, no `IllegalArgumentException` genérica.
- **DTO/proyección**: con entidad + MapStruct, extraer posición de la entidad **antes** del mapeo a DTO. Con proyección directa, recuperar todos los campos necesarios para la posición aunque no se expongan al cliente. MapStruct **condicional**.
- **Fetch**: `@EntityGraph` para `ToOne` solo cuando se devuelven entidades que necesitan la relación. Nunca fetch de colección en una consulta limitada. Usar batch fetching o dos fases; verificar N+1. Recomendar `spring.jpa.properties.hibernate.query.fail_on_pagination_over_collection_fetch=true` sin modificar configuración global automáticamente.
- **Índices**: sugerir índice compuesto de filtros por igualdad + claves de orden, por ejemplo `(status, created_at DESC, id DESC)`; verificar `EXPLAIN ANALYZE`. Filtros como `LIKE '%texto%'` pueden impedir búsquedas selectivas mediante B-tree convencional.
- **Salida**: generar imports, firmas concretas, inyección por constructor y código completo; no `TODO`, `...` ni pseudocódigo en los archivos Java finales.

## Plantillas de referencia (Keyset manual, DESC)
Ejemplo para `Product(id: Long, createdAt: Instant, status: Status)` con MapStruct:

```java
public record ProductKeysetPosition(Instant createdAt, Long id) {
    public ProductKeysetPosition {
        if (createdAt == null || id == null) {
            throw new InvalidKeysetPositionException("Keyset position must be complete");
        }
    }
}
```

```java
public record KeysetPageResponse<T, S, ID>(
    List<T> content,
    int size,
    boolean hasNext,
    S nextSortValue,
    ID nextId
) {}
```

```java
// Dentro de ProductRepository (hereda JpaRepository<Order, Long>):
@Query("""
    SELECT o FROM Product o
    WHERE o.status = :status
    ORDER BY o.createdAt DESC, o.id DESC
    """)
List<Product> findFirstWindow(@Param("status") Status status, Pageable limitOnly);

@Query("""
    SELECT o FROM Product o
    WHERE o.status = :status
      AND (o.createdAt < :lastCreatedAt
           OR (o.createdAt = :lastCreatedAt AND o.id < :lastId))
    ORDER BY o.createdAt DESC, o.id DESC
    """)
List<Product> findNextWindow(
    @Param("status") Status status,
    @Param("lastCreatedAt") Instant lastCreatedAt,
    @Param("lastId") Long lastId,
    Pageable limitOnly
);
```

```java
private static final int DEFAULT_LIMIT = 20;
private static final int MAX_LIMIT = 100;

@Transactional(readOnly = true)
public KeysetPageResponse<ProductDto, Instant, Long> findByStatus(
        Status status, ProductKeysetPosition position, Integer limit) {
    int effectiveLimit = limit == null ? DEFAULT_LIMIT : limit;
    if (effectiveLimit < 1 || effectiveLimit > MAX_LIMIT) {
        throw new InvalidPaginationException("Invalid limit: " + effectiveLimit
            + ". Expected 1 <= limit <= " + MAX_LIMIT);
    }
    Pageable limitOnly = PageRequest.of(0, effectiveLimit + 1);
    List<Product> rows = position == null
        ? productRepository.findFirstWindow(status, limitOnly)
        : productRepository.findNextWindow(status, position.createdAt(), position.id(), limitOnly);

    boolean hasNext = rows.size() > effectiveLimit;
    List<Product> visible = rows.subList(0, Math.min(rows.size(), effectiveLimit));
    Product last = visible.isEmpty() ? null : visible.get(visible.size() - 1);
    List<ProductDto> dtos = visible.stream().map(productMapper::toDto).toList();

    return new KeysetPageResponse<>(
        dtos, dtos.size(), hasNext,
        hasNext ? last.getCreatedAt() : null,
        hasNext ? last.getId() : null
    );
}
```

> En este ejemplo `InvalidPaginationException(String)` es el constructor adicional incluido en el skill Offset actualizado. Si el proyecto ya define la excepción común sin ese constructor, reutilizar un método factory equivalente o agregar una sobrecarga compatible; no generar una llamada a un constructor inexistente. Mantener todas las consultas y los filtros sincronizados.

## Variante opcional: Spring Data Keyset Scrolling
Usar `Window<T>` y `KeysetScrollPosition` si los filtros y las consultas pueden expresarse con métodos derivados, Query-by-Example o Querydsl compatibles y la versión de Spring Data JPA lo admite:

```java
Window<Product> findFirst20ByStatusOrderByCreatedAtDescIdDesc(
    Status status, KeysetScrollPosition position
);

// Primera ventana:
Window<Product> window = repository.findFirst20ByStatusOrderByCreatedAtDescIdDesc(
    status, ScrollPosition.keyset()
);
// Siguiente posición si window.hasNext() y !window.isEmpty():
KeysetScrollPosition nextPosition =
    (KeysetScrollPosition) window.positionAt(window.size() - 1);
```

El ejemplo nativo tiene límite fijo de 20; si se requiere límite dinámico, verificar capacidades de `Limit` en la versión seleccionada o usar implementación manual. **Spring Data JPA no soporta actualmente scrolling con métodos JPQL `@Query` basados en strings**. En keyset nativo, las proyecciones necesitan exponer internamente todos los campos de orden y de clave primaria usados para reconstruir la posición.

## Criterios de comprobación (sin generar tests)
Primera ventana; `limit` válido/inválido; exactamente `limit` vs `limit+1`; fechas empatadas; dirección ASC/DESC; filtros idénticos; inserción/eliminación entre ventanas; actualización de clave de orden; cursor incompleto; explicación del plan con índice.

## Cuándo elegir otro skill
- `pagination-offset-jpa`: saltar a página N y recuperar totales.
- `pagination-slice-jpa`: avanzar por páginas OFFSET sin calcular totales.
- `pagination-cursor-token-jpa`: misma estrategia Keyset pero con token público validado, versionado y eventualmente firmado/cifrado.

## Documentación oficial
- https://docs.spring.io/spring-data/commons/reference/repositories/scrolling.html
- https://docs.spring.io/spring-data/jpa/reference/jpa/query-methods.html
- https://docs.spring.io/spring-data/jpa/reference/repositories/projections.html
