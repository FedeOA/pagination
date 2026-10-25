---
name: pagination-cursor-token-jpa
description: "Generador interactivo de APIs con paginación Cursor Token sobre Keyset en Spring Boot 3 + JPA, cursor versionado y validado, DTO record, MapStruct opcional y respuesta propia. Ideal para APIs públicas/mobile con navegación opaca."
---

# Pagination Cursor Token JPA

## Alcance
Generar código Java 17+ para Spring Boot 3 / Spring Data JPA / Hibernate 6. El repositorio implementa **Keyset/Seek** (no `OFFSET` ni `COUNT(*)`); la API recibe/devuelve un **token de cursor** que representa la posición. El token no sustituye las verificaciones de autorización. No crear controllers, tests ni documentación de API salvo pedido expreso.

## Flujo interactivo
Preguntar **UNA A UNA** lo que todavía no se conozca; esperar respuesta:
1. Entidad y propiedad/tipo del ID; confirmar que puede ordenarse en el dialecto de BD.
2. Campos del DTO, asociaciones `ToOne` / `ToMany` y estrategia de proyección o entidad + MapStruct.
3. Filtros, orden estable e identificadores de contexto de acceso (p. ej. tenant) que deben mantenerse en las siguientes ventanas.
4. Columnas/tipos/direcciones de orden; desempate único y garantías de no-null/estabilidad.
5. Política de token: **opaco por contrato** (Base64Url JSON + HMAC) o **confidencial** (AES-GCM/identificador aleatorio); expiración sí/no, rotación de claves, `defaultLimit`, `maxLimit` y si cambios de limit están permitidos.
6. Paquete base, mecanismo de configuración segura de claves y componentes existentes.
Resumir y confirmar antes de generar; no pedir información que el usuario ya haya proporcionado. No asumir que codificar en Base64 oculta los datos.

## Archivos a generar
- `<Entity>Dto.java` (record).
- `CursorPageResponse.java` (record genérico, reutilizable).
- `<Entity>CursorPayload.java` (record tipado con posición y metadatos).
- `CursorTokenCodec.java` y su **implementación concreta** (ej. `HmacCursorTokenCodec.java` o `AesGcmCursorTokenCodec.java`), con inyección de claves desde configuración segura.
- `<Entity>Repository.java` y `<Entity>Service.java`.
- `<Entity>Mapper.java` **solo** para entidad + MapStruct.
- `InvalidCursorException.java` y `InvalidPaginationException.java` si el proyecto no tiene equivalentes.
No generar clases comunes duplicadas ni sobreescribir clases existentes sin verificar su compatibilidad.

## Reglas obligatorias: consulta y respuesta
- Implementar **Keyset real**: orden total con desempate único, consulta inicial y de continuación o variante `Window<T>` compatible; nunca un OFFSET con un token que solo codifica números de página.
- Para seguir el orden `(createdAt DESC, id DESC)`, predicado `createdAt < lastCreatedAt OR (createdAt = lastCreatedAt AND id < lastId)`. Adaptar comparaciones a ASC, DESC, direcciones mixtas y cantidad de columnas.
- Mantener filtros y orden idénticos a los asociados al token, y volver a aplicar autorización y filtros de tenant/propiedad en **cada** consulta.
- Exigir claves de ordenamiento no nulas y preferiblemente inmutables; verificar soporte de orden/comparación según dialecto; preservar precisión de `Instant`, `LocalDateTime`, decimales y claves grandes.
- En implementación manual recuperar `limit + 1` con `PageRequest.of(0, limit + 1)`; `hasNext = rows.size() > limit`; devolver máximo `limit` elementos. `nextCursor` se construye usando **el último elemento realmente devuelto**, no la fila extra; `nextCursor = null` si `hasNext` es falso. `size = content.size()`.
- `limit == null` usa `defaultLimit`; validar `1 <= defaultLimit <= maxLimit < Integer.MAX_VALUE` y `1 <= limit <= maxLimit`; reutilizar `InvalidPaginationException` del proyecto cuando exista.
- Proyecciones directas no requieren MapStruct; si se generan entidades + Mapper, extraer la posición antes de convertir al DTO. Incluir los campos Keyset en cualquier proyección interna aunque no se expongan públicamente.
- `@EntityGraph` solo en relaciones ToOne necesarias para mapping de entidades. Nunca `JOIN FETCH` de colecciones con límite; preferir batch fetching o consulta en dos fases. Recomendar `spring.jpa.properties.hibernate.query.fail_on_pagination_over_collection_fetch=true` sin cambiar configuración global sin autorización.
- Índices según filtros de igualdad + orden (`status, created_at DESC, id DESC`); verificar planes con `EXPLAIN ANALYZE`. Documentar que Keyset no proporciona snapshot entre peticiones ni resuelve cambios en columnas de orden.

## Reglas obligatorias: token y seguridad
- **Opacidad contractual vs confidencialidad**: el cliente no debe inspeccionar el token. Base64Url + JSON **no cifra**; HMAC verifica integridad/autenticidad pero **no** oculta los campos. Para ocultar valores usar cifrado autenticado (AES-GCM con nonce único) o token aleatorio con estado servidor.
- **Integridad**: modalidad firmada predeterminada HMAC-SHA256, con claves aleatorias seguras >= 256 bits, obtenidas desde configuración externa/secret manager, nunca hardcodeadas ni registradas. Formato versionado y explícito (p. ej. `base64url(header).base64url(payload).base64url(mac)`), con `kid` para rotación. Codificar en UTF-8; usar Base64Url de forma consistente.
- **Validación**: imponer longitud máxima y estructura estricta; identificar `kid` únicamente contra un conjunto permitido; verificar MAC **antes de confiar en el payload**, con comparación resistente a timing (`MessageDigest.isEqual` para bytes de MAC de longitud fija), luego parsear y validar versión, tipos, integridad de posición, expiración (si se exige) y contexto. Rechazar firmas inválidas, formato malformado, claves desconocidas y cursores parciales.
- **Contexto del cursor**: incluir huella criptográfica de filtros normalizados, orden/direcciones, versión del esquema de consulta y ámbito de autorización (p. ej. tenant/usuario si corresponde). Calcularla de forma determinista y volver a compararla con la consulta recibida; no admitir reutilización del token para otro filtro/orden. Definir si `limit` debe permanecer fijo o puede variar.
- **Expiración**: cuando esté activada, incorporar `iat`/`exp` y verificar tiempo actual con un `Clock` inyectable y margen permitido definido; una expiración por sí sola no garantiza que las filas no cambien. Permitir rotación mediante `kid`, reteniendo claves viejas únicamente durante la ventana requerida.
- **Errores**: token ausente = primera ventana; token vacío o inválido = `InvalidCursorException`; mensajes externos genéricos, sin filtrar claves, MAC, payload ni datos sensibles. No registrar tokens completos. Manejo HTTP 400 delegado al `@ControllerAdvice` global, no generarlo.
- **Autorización**: el cursor es dato de navegación, no una credencial. Aplicar controles de seguridad en cada lectura. Evitar datos personales/sensibles dentro de tokens legibles.
- **Calidad**: generar codec **funcional completo**, imports, parámetros configurables, inyección por constructor y clases del payload que realmente compilen. No dejar `TODO`, `...`, comentarios vacíos ni una interfaz sin implementación en los archivos generados. Si el proyecto no especifica proveedor criptográfico/configuración, elegir una alternativa segura estándar y explicar las variables de entorno requeridas sin insertar secretos ficticios como si fueran reales.

## Plantillas de referencia
Ejemplo generado para una orden `id: Long`, `createdAt: Instant`, con expiración habilitada; adaptar tipos y omitir los campos de expiración cuando el contrato no la utilice.

```java
public record CursorPageResponse<T>(
    List<T> content,
    int size,
    boolean hasNext,
    String nextCursor
) {}
```

```java
// El payload es INTERNO: nunca se devuelve como JSON de respuesta al consumidor.
public record OrderCursorPayload(
    int version,
    Instant createdAt,
    Long id,
    String queryFingerprint,
    long issuedAtEpochSeconds,
    long expiresAtEpochSeconds
) {}
```

```java
public interface CursorTokenCodec {
    String encode(OrderCursorPayload payload);
    OrderCursorPayload decodeAndVerify(String token);
}
```

```java
// Contrato de servicio que debe implementarse íntegramente en el código generado:
@Transactional(readOnly = true)
public CursorPageResponse<OrderDto> findByCursor(
        Status status, String cursor, Integer limit);
```

### Algoritmo requerido del servicio (no entregar pseudocódigo como archivo Java final)
1. Normalizar/validar `limit`; canonicalizar filtros, orden y ámbito de autorización actual.
2. Si no hay cursor, utilizar primera consulta Keyset. Si existe, `codec.decodeAndVerify`, verificar fingerprint/contexto y extraer posición tipada.
3. Obtener como máximo `limit + 1` entidades/proyecciones con query Keyset y filtros/autorización actuales.
4. Determinar `hasNext`, truncar a `limit`, extraer posición del **último incluido**.
5. Mapear los elementos al DTO. Solo si hay siguiente ventana, crear payload versionado con posición/contexto/tiempos y generar `nextCursor` con codec.
6. Devolver `CursorPageResponse<>(dtos, dtos.size(), hasNext, nextCursor)`; para fin de resultados `nextCursor = null`.

### Implementación requerida del codec HMAC
- Definir formato binario/textual versionado que delimite header, payload y MAC de manera inequívoca.
- Incluir `kid` en header, sin confiar en sus valores hasta validar MAC con clave permitida.
- Serializar payload JSON con Jackson usando soporte `java.time` cuando corresponda; preservar precisión de fechas y números.
- Calcular `HmacSHA256(headerCodificado + "." + payloadCodificado)` y codificar MAC con Base64Url sin padding.
- Comprobar longitud exacta de MAC (32 bytes para HMAC-SHA256), verificar firma en bytes; **solo luego** deserializar/usar payload. Aplicar controles semánticos y de expiración/contexto fuera o dentro del codec con una frontera documentada.
- Especificar rotación y origen seguro de claves (por ejemplo propiedad que referencia un secreto); usar una clave de firma con suficiente entropía. No usar cifrado casero.

## Criterios de comprobación (sin generar tests)
Primera y última ventana; `limit` omitido/inválido; exactamente `limit` y `limit + 1`; tampering de payload/firma; token vacío, corrupto, muy grande, expirado, versión desconocida y `kid` desconocido; filtros/tenant diferentes; cambios de orden; datos empatados; inserciones/eliminaciones concurrentes; precisión temporal; ausencia de `OFFSET`/`COUNT` y análisis de índice.

## Cuándo elegir otro skill
- `pagination-keyset-jpa`: bastan valores de posición tipados, sin token para cliente.
- `pagination-offset-jpa`: se necesitan totales y salto directo a páginas numeradas.
- `pagination-slice-jpa`: basta navegación OFFSET con `hasNext` sin totales.

## Documentación oficial
- https://docs.spring.io/spring-data/commons/reference/repositories/scrolling.html
- https://docs.spring.io/spring-data/jpa/reference/jpa/query-methods.html
- https://docs.hibernate.org/orm/6.6/javadocs/org/hibernate/cfg/QuerySettings.html
