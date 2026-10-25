---
name: pagination-offset-jpa
description: "Generador interactivo de paginación numerada (offset + Page) en Spring Boot 3 y Spring Data JPA, con DTO record, MapStruct opcional y PageResponse propio. Usar para listados que necesitan totalElements/totalPages y acceso a páginas específicas."
---

# Pagination Offset JPA

## Alcance
Generar código Java 17+ para Spring Boot 3 / Spring Data JPA / Hibernate 6. Utilizar `Page<T>` y `PageRequest`, con paginación **basada en OFFSET**. No confundir esta variante con `Slice<T>` ni con Keyset. No crear controllers, tests ni documentación de API salvo petición expresa.

## Flujo interactivo
Preguntar **UNA A UNA** las cuestiones que no estén ya resueltas por el contexto; esperar cada respuesta:
1. Entidad y tipo de ID (incluida la propiedad JPA de clave primaria).
2. Campos del DTO record, relaciones necesarias (`ToOne` / `ToMany`) y si conviene **proyección directa** o **entidad + MapStruct**.
3. Filtros fijos/opcionales del listado y sus tipos.
4. Orden por defecto, desempate único y, si hay orden externo, campos permitidos (`allowlist`).
5. Base pública de página (`0` o `1`), `defaultSize`, `maxSize` y página por defecto.
6. Paquete base y convenciones o componentes reutilizables existentes.
Resumir lo acordado, pedir confirmación y generar los archivos. No volver a preguntar datos ya proporcionados. Si faltan detalles no esenciales, elegir valores seguros y explicitar los supuestos.

## Archivos a generar
- `<Entity>Dto.java` (record; nunca exponer entidades JPA).
- `PageResponse.java` (record genérico; reutilizar si existe y es compatible).
- `<Entity>Repository.java`.
- `<Entity>Service.java`.
- `<Entity>Mapper.java` **solo** si se recuperan entidades y se necesitan transformar con MapStruct (`@Mapper(componentModel = "spring")`).
- `InvalidPaginationException.java` **solo** si el proyecto no dispone de una excepción equivalente.
No sobrescribir componentes compartidos sin comprobar su contrato.

## Reglas obligatorias
- **Entrada**: `page` es público y usa la base elegida; `size` opcional usa `defaultSize` cuando se omite. Validar `base ∈ {0,1}`, `page >= base` y `1 <= size <= maxSize`. Validar `1 <= defaultSize <= maxSize`. Convertir `internalPage = page - base` antes de `PageRequest.of`.
- **Salida**: devolver `PageResponse.page` en la **misma base pública** (`page.getNumber() + base`). `size` indica tamaño solicitado; `totalElements`, `totalPages`, `hasNext`, `hasPrevious` provienen del `Page`.
- **Orden**: siempre determinista; agregar una clave única como último desempate (ej. `createdAt DESC, id DESC`). Si existe sort externo, validar propiedades y direcciones contra una allowlist; nunca concatenar expresiones sin validar ni usar `JpaSort.unsafe` con entrada sin confianza. No repetir el desempate si la combinación ya es única.
- **Repositorio**: método derivado `findBy...(..., Pageable)` para casos simples; utilizar `@Query` o `JpaSpecificationExecutor` para filtros opcionales o complejos. Un `Page<T>` **puede** necesitar un `COUNT`; si hay joins complejos, verificar el conteo y definir `countQuery` cuando corresponda. Evitar que joins `ToMany` multipliquen filas de la entidad raíz.
- **DTO**: si es plano y compatible, preferir proyección directa `Page<EntityDto>` (record/interface), sin mapper adicional. Para JPQL complejo, usar `SELECT new paquete.EntityDto(...)` cuando corresponda. Si requiere transformaciones, cargar entidad + `Page.map(mapper::toDto)`. No exigir simultáneamente proyección directa y MapStruct.
- **Relaciones**: `ToOne` con entidad + mapper: considerar `@EntityGraph(attributePaths = {...})` **solo** para relaciones realmente usadas; proyección directa no requiere `EntityGraph` automático. No paginar sobre `JOIN FETCH` de colecciones. Para `ToMany`, usar carga por lotes o estrategia en dos pasos (IDs paginados → asociaciones), o una proyección cuidadosamente diseñada; verificar ausencia de N+1.
- **Hibernate**: recomendar habilitar `spring.jpa.properties.hibernate.query.fail_on_pagination_over_collection_fetch=true` (propiedad del proyecto, no generar configuración global sin permiso).
- **Servicio**: `@Transactional(readOnly = true)`; `InvalidPaginationException` con valores inválidos y límites permitidos. El manejador HTTP global pertenece al proyecto: no generarlo. Las validaciones deben ocurrir antes de `PageRequest.of`.
- **Rendimiento**: proponer índice coherente con filtros por igualdad y el orden, por ejemplo `(status, created_at DESC, id DESC)`; analizar con `EXPLAIN ANALYZE`, no asumir que todo índice será usado.
- **Concurrencia**: documentar que `Page` con OFFSET puede duplicar u omitir elementos entre peticiones independientes si se insertan/eliminan filas antes de la posición. Orden determinista no da snapshot consistente.
- **Calidad**: generar imports, inyección por constructor, nombres coherentes y código que compile con los tipos reales. No dejar `TODO`, `...` ni firmas de ejemplo en archivos finales.

## Plantillas de referencia (variante entidad + MapStruct)

```java
public record PageResponse<T>(
    List<T> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean hasNext,
    boolean hasPrevious
) {
    public static <T> PageResponse<T> from(Page<T> p, int base) {
        return new PageResponse<>(
            p.getContent(), p.getNumber() + base, p.getSize(),
            p.getTotalElements(), p.getTotalPages(), p.hasNext(), p.hasPrevious()
        );
    }
}
```

```java
// Para el ejemplo Order(customer) + Status:
@EntityGraph(attributePaths = "customer") // omitir si el DTO no usa customer
Page<Order> findByStatus(Status status, Pageable pageable);
```

```java
private static final int PAGE_BASE = 1; // valor configurado (0 o 1)
private static final int DEFAULT_SIZE = 20;
private static final int MAX_SIZE = 100;

@Transactional(readOnly = true)
public PageResponse<OrderDto> findByStatus(Status status, Integer page, Integer size) {
    int effectivePage = page == null ? PAGE_BASE : page;
    int effectiveSize = size == null ? DEFAULT_SIZE : size;
    if (effectivePage < PAGE_BASE || effectiveSize < 1 || effectiveSize > MAX_SIZE) {
        throw new InvalidPaginationException(effectivePage, effectiveSize, PAGE_BASE, MAX_SIZE);
    }
    Pageable pageable = PageRequest.of(effectivePage - PAGE_BASE, effectiveSize,
        Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("id")));
    Page<OrderDto> result = orderRepository.findByStatus(status, pageable)
        .map(orderMapper::toDto);
    return PageResponse.from(result, PAGE_BASE);
}
```

```java
public class InvalidPaginationException extends RuntimeException {
    public InvalidPaginationException(int page, int size, int base, int maxSize) {
        super("Invalid pagination: page=" + page + ", size=" + size
            + ". Expected page >= " + base + " and 1 <= size <= " + maxSize);
    }

    public InvalidPaginationException(String message) {
        super(message);
    }
}
```

> Adaptar los ejemplos a los nombres, tipos, filtros, columnas y componentes existentes. En la variante **proyección**, el repositorio devuelve `Page<OrderDto>` y el servicio **no** aplica `mapper::toDto`.

## Criterios de comprobación (sin generar tests)
Primera página, base 0/1, parámetros omitidos, tamaños fuera de rango, sin resultados, última página, empates en el orden, filtro opcional, totales correctos, joins con colecciones y análisis de SQL/`COUNT`.

## Cuándo elegir otro skill
- `pagination-slice-jpa`: solo interesa `hasNext`, no totales.
- `pagination-keyset-jpa`: offsets profundos o necesidad de mitigar desplazamientos por inserts/deletes.
- `pagination-cursor-token-jpa`: Keyset con un token de navegación público.

## Documentación oficial
- https://docs.spring.io/spring-data/commons/reference/repositories/query-methods-details.html
- https://docs.spring.io/spring-data/jpa/reference/repositories/projections.html
- https://docs.hibernate.org/orm/6.6/javadocs/org/hibernate/cfg/QuerySettings.html
