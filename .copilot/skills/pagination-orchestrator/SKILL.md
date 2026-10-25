---
name: pagination-orchestrator
description: "Orquestador de paginacion reusable. Recopila contexto, decide entre offset/slice/keyset/cursor-token y delega al skill correcto. Trigger elegir estrategia de paginacion, selector pagination, orchestrate pagination skills."
---

# Pagination Orchestrator

## Objetivo
Seleccionar la estrategia de paginacion correcta para cualquier proyecto y delegar la implementacion al skill especializado:
- `pagination-offset-jpa`
- `pagination-slice-jpa`
- `pagination-keyset-jpa`
- `pagination-cursor-token-jpa`

## Flujo obligatorio
1. Recolecta contexto minimo antes de decidir.
2. Si faltan datos criticos, pregunta en bloque corto (max 6 preguntas).
3. Aplica la matriz de decision.
4. Si hay empate, explicita trade-offs y pide 1 confirmacion.
5. Delega al skill ganador.
6. Devuelve decision + razon + datos usados + supuestos.

## Contexto minimo requerido
- Dominio y entidad objetivo.
- Volumen esperado (bajo/medio/alto) y profundidad de navegacion (paginas bajas vs paginas altas).
- Si el cliente necesita `totalElements` y `totalPages`.
- Tipo de consumidor (interno/backoffice vs API publica/mobile).
- Requisito de estabilidad ante inserts/deletes concurrentes.
- Orden estable disponible (campo principal + desempate por id).

## Preguntas de aclaracion (si faltan datos)
1. Necesitas totales globales (`totalElements`, `totalPages`)?
2. El listado llega a paginas altas con frecuencia?
3. La API es publica y queres ocultar detalles internos de orden?
4. El orden puede ser estable y determinista (`sortField`, `id`)?
5. Priorizas simplicidad o performance en alto volumen?
6. Queres evitar `count(*)` por costo?

## Matriz de decision
- Elegir `offset` cuando:
  - Se requieren totales globales.
  - El uso principal es backoffice/admin.
  - Profundidad de pagina baja o media.
- Elegir `slice` cuando:
  - No se requieren totales globales.
  - Se busca menor costo que `Page`.
  - Solo importa `hasNext`.
- Elegir `keyset` cuando:
  - Hay alto volumen o paginas profundas.
  - Se necesita estabilidad alta con concurrencia.
  - Existe orden estable (`sortField + id`).
- Elegir `cursor-token` cuando:
  - El consumidor es API publica/mobile.
  - Se quiere cursor opaco para no exponer detalles internos.
  - Tambien aplica volumen alto (internamente usa keyset).

## Reglas de desempate
1. Si API publica + ocultar estructura interna: `cursor-token` gana sobre `keyset`.
2. Si requiere totales globales: `offset` gana sobre `slice`.
3. Si volumen alto y no requiere totales: `keyset` gana sobre `offset`.
4. Si no hay orden estable posible: caer a `offset` o `slice` segun necesidad de totales.

## Criterios de no decision
No decidir aun y pedir datos cuando falte cualquiera de:
- necesidad de totales,
- tipo de consumidor,
- volumen/profundidad,
- posibilidad de orden estable.

## Formato de salida obligatorio
Responder en este formato:

```text
Decision: <offset|slice|keyset|cursor-token>
Delegar a: <skill-name>
Razon principal: <1-2 lineas>
Contexto usado: <lista corta>
Supuestos: <lista corta o ninguno>
Riesgo principal: <1 linea>
```

## Delegacion
- Si `Decision=offset` -> delegar a `pagination-offset-jpa`.
- Si `Decision=slice` -> delegar a `pagination-slice-jpa`.
- Si `Decision=keyset` -> delegar a `pagination-keyset-jpa`.
- Si `Decision=cursor-token` -> delegar a `pagination-cursor-token-jpa`.

## Notas
- Mantener neutralidad tecnologica al decidir (la implementacion puede ser JPA, JDBC u otra).
- Si el proyecto no usa JPA, conservar la decision y adaptar el skill de implementacion equivalente.

