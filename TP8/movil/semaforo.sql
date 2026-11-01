-- semaforo.sql: simulacion de sincronizacion entre la tablet y el servidor (Consigna 2.b).
-- Clasifica solicitudes PENDIENTE contra la ultima snapshot_servidor.
-- Idempotente: solo evalua solicitudes con estado = 'PENDIENTE'.
-- No modifica PostgreSQL (la tablet nunca escribe en el servidor).

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

UPDATE cola_sync
SET
  -- ==========================================================================
  -- CASE del semaforo (rojo -> RECHAZADO, amarillo -> CONFLICTO, verde -> SIMULADO_APROBADO)
  -- Consigna 2.b:
  --   1. Borrador vacio (n_items = 0) o rechazo por servidor (n_rojo > 0) -> 'RECHAZADO'
  --      El rojo tiene prioridad estricta sobre el amarillo (ej. baja + cambio de precio).
  --   2. Sin causa de rechazo pero con cambio de precio (n_amarillo > 0) -> 'CONFLICTO'
  --   3. Coincidencia total en disponibilidad, stock y precio -> 'SIMULADO_APROBADO'
  -- ==========================================================================
  estado = CASE
    WHEN ev.n_items = 0 OR ev.n_rojo > 0 THEN 'RECHAZADO'
    WHEN ev.n_amarillo > 0 THEN 'CONFLICTO'
    ELSE 'SIMULADO_APROBADO'
  END,
  motivo = ev.motivo,
  evaluada_en = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
  snapshot_copiado_en = (SELECT max(copiado_en) FROM snapshot_servidor)
FROM (
  SELECT
    c.solicitud_uuid,
    count(i.producto_id) AS n_items,
    sum(CASE
      WHEN i.producto_id IS NOT NULL AND (s.id IS NULL OR s.eliminado = 1 OR s.disponible = 0 OR i.cantidad > s.stock)
      THEN 1 ELSE 0
    END) AS n_rojo,
    sum(CASE
      WHEN i.producto_id IS NOT NULL AND s.id IS NOT NULL AND s.eliminado = 0 AND s.disponible = 1 AND i.cantidad <= s.stock AND i.precio_centavos_visto <> s.precio_centavos
      THEN 1 ELSE 0
    END) AS n_amarillo,
    CASE
      WHEN count(i.producto_id) = 0 THEN 'borrador vacio'
      ELSE group_concat(
        CASE
          WHEN i.producto_id IS NULL THEN NULL
          WHEN s.id IS NULL THEN 'producto ' || i.producto_id || ': no existe en el servidor'
          WHEN s.eliminado = 1 THEN 'producto ' || i.producto_id || ': dado de baja'
          WHEN s.disponible = 0 THEN 'producto ' || i.producto_id || ': no disponible'
          WHEN i.cantidad > s.stock THEN 'producto ' || i.producto_id || ': pide ' || i.cantidad || ', stock ' || s.stock
          WHEN i.precio_centavos_visto <> s.precio_centavos THEN 'producto ' || i.producto_id || ': precio visto ' || i.precio_centavos_visto || ', actual ' || s.precio_centavos
          ELSE NULL
        END, '; '
      )
    END AS motivo
  FROM cola_sync c
  -- LEFT JOIN hacia item_borrador: necesario para detectar borradores vacios (count = 0)
  -- y no dejarlos colgados en PENDIENTE para siempre.
  LEFT JOIN item_borrador i ON i.id_local = c.id_local
  -- LEFT JOIN hacia snapshot_servidor: permite detectar productos que existian localmente
  -- pero fueron borrados o no estan en la instantanea del servidor (s.id IS NULL -> inexistente).
  LEFT JOIN snapshot_servidor s ON s.id = i.producto_id
  -- Solo se evaluan solicitudes PENDIENTE: los estados terminales (SIMULADO_APROBADO,
  -- CONFLICTO, RECHAZADO) son inmutables e historicos, garantizando idempotencia.
  WHERE c.estado = 'PENDIENTE'
  GROUP BY c.solicitud_uuid
) ev
WHERE cola_sync.solicitud_uuid = ev.solicitud_uuid
  -- Guarda de instantanea vacia: si no hay datos del servidor, ninguna solicitud sale de PENDIENTE.
  AND EXISTS (SELECT 1 FROM snapshot_servidor);

SELECT changes();

COMMIT;
