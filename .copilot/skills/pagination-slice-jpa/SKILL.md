---
name: pagination-slice-jpa
description: "Generador interactivo de paginación Slice con OFFSET en Spring Boot 3 y Spring Data JPA, DTO record, MapStruct opcional y SliceResponse propio. Usar cuando importa hasNext pero no los totales globales."
---

# Pagination Slice JPA

## Alcance
Generar código Java 17+ para Spring Boot 3 / Spring Data JPA / Hibernate 6 usando `Slice<T>` con `Pageable`. `Slice` **evita consultar el total**, pero cuando se usa `PageRequest` sigue siendo paginación **OFFSET**. No generar controllers, tests ni documentación de API salvo solicitud.

## Flujo interactivo
Preguntar **UNA A UNA** los datos todavía no conocidos; esperar respuesta:
1. Entidad, propiedad y tipo de ID.
2. Campos del DTO record, asociaciones `ToOne`/`ToMany` y estrategia de salida (proyección directa o entidad + MapStruct).
3. Filtros y sus tipos (obligatorios y opcionales).
4. Orden por defecto, desempate único y allowlist de sort externo si corresponde.
5. Base pública (`0`/`1`), `defaultSize`, `maxSize` y página predeterminada.
6. Paquete base y componentes comunes existentes.
Resumir y confirmar antes de generar. Reutilizar respuestas ya dadas y evitar duplicar clases comunes.

## Archivos a generar
- `<Entity>Dto.java` (record).
- `SliceResponse.java` (record genérico; reutilizable).
- `<Entity>Repository.java`.
- `<Entity>Service.java`.
- `<Entity>Mapper.java` **solo** para entidad + MapStruct.
- `InvalidPaginationException.java` si no hay equivalente común.

## Reglas obligatorias
- **Repositorio**: retornar `Slice<Entity>` o `Slice<Projection>`, **no** `Page` ni una lista sin metadatos. Un Slice ordinario solicita usualmente `size + 1` filas para calcular `hasNext`, sin `COUNT(*)` para obtener totales. No añadir `totalElements` o `totalPages` a la respuesta.
- **Contrato**: `SliceResponse<T>(content, page, size, hasNext, hasPrevious)`; `page` usa base pública, `size` es el tamaño solicitado (`s.getSize()`). No confundirlo con `content.size()`.
- **Entrada**: normalizar nulls con `page = base` y `size = defaultSize`. `base ∈ {0,1}`; `1 <= defaultSize <= maxSize`; validar `page >= base` y `1 <= size <= maxSize` antes de `PageRequest.of(page - base, size, ...)`.
- **Errores**: reutilizar `InvalidPaginationException` (no `IllegalArgumentException` genérico); no generar el `@ControllerAdvice` del proyecto.
- **Orden**: siempre determinista con desempate único (ej. `createdAt DESC, id DESC`). Sort de usuario solo desde allowlist, con desempate final garantizado.
- **DTO**: para proyección directa `Slice<Dto>`, **no** generar MapStruct ni hacer `slice.map(mapper::toDto)`. Para `Slice<Entity>`, generar Mapper y transformar mediante `slice.map(mapper::toDto)`. Los records/proyecciones con joins deben validarse según JPA.
- **Relaciones**: `@EntityGraph` para ToOne solo si la entidad se mapea y el DTO usa esas asociaciones; no asociarlo mecánicamente a una proyección. Nunca `JOIN FETCH` de colección con `Slice` paginado; batch fetching o consulta de dos fases. Revisar N+1 y filas duplicadas por joins `ToMany`.
- **Configuración sugerida**: `spring.jpa.properties.hibernate.query.fail_on_pagination_over_collection_fetch=true`, solo como recomendación, no modificar configuración de proyecto automáticamente.
- **Índices**: según filtros y orden, por ejemplo `(status, created_at DESC, id DESC)`; verificar plan con `EXPLAIN ANALYZE`.
- **Concurrencia**: `Slice` + `PageRequest` **no** elimina las anomalías de OFFSET frente a inserciones/eliminaciones entre peticiones; tampoco garantiza snapshot.
- **Código final**: imports completos, inyección por constructor, sin `TODO`, `...` ni dependencias faltantes.

## Plantillas de referencia (entidad + MapStruct)

```java
public record SliceResponse<T>(
    List<T> content,
    int page,
    int size,
    boolean hasNext,
    boolean hasPrevious
) {
    public static <T> SliceResponse<T> from(Slice<T> s, int base) {
        return new SliceResponse<>(
            s.getContent(), s.getNumber() + base, s.getSize(), s.hasNext(), s.hasPrevious()
        );
    }
}
```

```java
Slice<Order> findByStatus(Status status, Pageable pageable);
```

```java
private static final int PAGE_BASE = 1;
private static final int DEFAULT_SIZE = 20;
private static final int MAX_SIZE = 100;

@Transactional(readOnly = true)
public SliceResponse<OrderDto> findByStatus(Status status, Integer page, Integer size) {
    int effectivePage = page == null ? PAGE_BASE : page;
    int effectiveSize = size == null ? DEFAULT_SIZE : size;
    if (effectivePage < PAGE_BASE || effectiveSize < 1 || effectiveSize > MAX_SIZE) {
        throw new InvalidPaginationException(effectivePage, effectiveSize, PAGE_BASE, MAX_SIZE);
    }
    Pageable pageable = PageRequest.of(effectivePage - PAGE_BASE, effectiveSize,
        Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("id")));
    Slice<OrderDto> result = orderRepository.findByStatus(status, pageable)
        .map(orderMapper::toDto);
    return SliceResponse.from(result, PAGE_BASE);
}
```

> Para **proyección directa** el repositorio devuelve `Slice<OrderDto>` y se devuelve `SliceResponse.from(slice, PAGE_BASE)` sin mapper. Reutilizar `InvalidPaginationException` compatible con el skill Offset.

## Criterios de comprobación (sin generar tests)
Primera/última ventana, sin resultados, `hasNext` con exactamente `size` y con `size + 1`, página base 0/1, límites inválidos, orden con empates, N+1, ausencia de `COUNT(*)` en las consultas ordinarias y comportamiento con offsets elevados.

## Cuándo elegir otro skill
- `pagination-offset-jpa`: se necesitan total de elementos y páginas.
- `pagination-keyset-jpa`: se priorizan páginas profundas y resistencia a desplazamientos por inserciones/eliminaciones.
- `pagination-cursor-token-jpa`: navegación Keyset por token en una API externa.

## Documentación oficial
- https://docs.spring.io/spring-data/commons/reference/repositories/query-methods-details.html
- https://docs.spring.io/spring-data/jpa/reference/repositories/projections.html
- https://docs.hibernate.org/orm/6.6/javadocs/org/hibernate/cfg/QuerySettings.html
