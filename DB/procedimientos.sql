-- Active: 1783038914702@@localhost@3306@cuatro
-- TRACEX — Procedimientos almacenados
-- Version: 2026-07-31
--
-- Qué hay aquí
-- ------------
-- Operaciones que tocan muchas filas de varias tablas y tienen que pasar o no
-- pasar completas. En Python serían un bucle de N viajes a la base sin
-- atomicidad real; aquí son una sola llamada y una sola transacción.
--
-- NO son reglas de negocio sueltas: esas viven en DB/triggers.sql. Los cuatro
-- primeros son acciones que alguien dispara a propósito desde una pantalla; el
-- quinto (sp_Dashboard_Resumen) es la excepción y su propio comentario lo dice.
--
-- Cómo se cargan (después de estructura.sql, vistas.sql y triggers.sql):
--
--     mysql -u root cuatro < DB/procedimientos.sql
--
-- Es idempotente por los DROP de abajo: córrelo las veces que quieras.
--
-- Convención de errores
-- ---------------------
-- Igual que los triggers: SIGNAL SQLSTATE '45000' con el texto en español y el
-- prefijo 'Error sp_Nombre:'. La API ya sabe traducir eso a un 400 legible
-- (ver api/errores.py, mensaje_de_base), así que el motivo llega a pantalla
-- sin escribir nada extra.
--
-- Cada procedimiento termina con un SELECT de resumen. Se usa SELECT y no
-- parámetros OUT porque mysqlclient deja los OUT en variables de sesión
-- (@_sp_nombre_0) que luego hay que ir a consultar aparte; un SELECT final se
-- lee directo con cursor.fetchall().


USE cuatro;

DROP PROCEDURE IF EXISTS sp_Liberar_Componentes_Laptop;
DROP PROCEDURE IF EXISTS sp_Cancelar_Orden_Produccion;
DROP PROCEDURE IF EXISTS sp_Iniciar_Ensamblaje_Orden;
DROP PROCEDURE IF EXISTS sp_Recibir_Orden_Material;
DROP PROCEDURE IF EXISTS sp_Dashboard_Resumen;

DELIMITER $$


-- ============================================================
-- 1. sp_Liberar_Componentes_Laptop
-- ============================================================
--
-- Objetivo : Desarmar una laptop. Suelta todos los componentes que tiene
--            montados, los devuelve al inventario y cierra su ensamblaje.
--
-- Parámetros:
--   numeroLaptop   Número de la laptop a desarmar.
--   estadoDestino  A qué estado regresan los componentes:
--                    EDC001 (Disponible) si sirven y vuelven al inventario
--                    EDC003 (Dañado)     si salieron defectuosos
--                  NULL se toma como EDC001.
--
-- Qué NO toca:
--   - Los componentes Mermados (EDC004). Están perdidos, no regresan al
--     inventario, y se les deja su vínculo con el ensamblaje para que el
--     historial siga diciendo en qué laptop se perdieron.
--   - El estado de la laptop. Quien llama decide qué hacer con ella
--     (sp_Cancelar_Orden_Produccion, por ejemplo, la pasa a Rechazada).
--
-- OJO: al cerrar el ensamblaje (fecha_fin), tg_Validar_Apertura_Ensamblaje
--   impide abrirle uno nuevo a esa laptop. O sea que desarmarla es definitivo:
--   ya no se vuelve a armar. Es a propósito, para no perder el historial.

CREATE PROCEDURE sp_Liberar_Componentes_Laptop(
    IN numeroLaptop  INT,
    IN estadoDestino VARCHAR(8)
)
BEGIN
    DECLARE destino_componentes VARCHAR(8);
    DECLARE laptop_existe       INT;
    DECLARE total_liberados     INT DEFAULT 0;
    DECLARE total_mermados      INT DEFAULT 0;
    DECLARE total_cerrados      INT DEFAULT 0;

    SET destino_componentes = IFNULL(estadoDestino, 'EDC001');

    -- Validaciones

    SELECT COUNT(*) INTO laptop_existe FROM laptop WHERE numero = numeroLaptop;

    IF laptop_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Liberar_Componentes_Laptop: esa laptop no existe';
    END IF;

    IF destino_componentes NOT IN ('EDC001', 'EDC003') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Liberar_Componentes_Laptop: los componentes solo pueden regresar a Disponible o Dañado';
    END IF;

    -- Cuántos se van a quedar como están, para reportarlo
    SELECT COUNT(*)
      INTO total_mermados
      FROM componente c
      JOIN registro_ensamblaje re ON re.numero = c.registro_ensamblaje
     WHERE re.laptop = numeroLaptop
       AND c.estado  = 'EDC004';

    -- Soltar los componentes montados.
    -- El estado admite nulos, así que se compara con IS NULL OR <>: un
    -- 'NULL <> EDC004' no es TRUE, es NULL, y esas filas se quedarían fuera.
    UPDATE componente c
      JOIN registro_ensamblaje re ON re.numero = c.registro_ensamblaje
       SET c.estado              = destino_componentes,
           c.registro_ensamblaje = NULL
     WHERE re.laptop = numeroLaptop
       AND (c.estado IS NULL OR c.estado <> 'EDC004');

    SET total_liberados = ROW_COUNT();

    -- Cerrar los ensamblajes que siguieran abiertos
    UPDATE registro_ensamblaje
       SET fecha_fin = CURDATE(),
           hora_fin  = CURTIME()
     WHERE laptop    = numeroLaptop
       AND fecha_fin IS NULL;

    SET total_cerrados = ROW_COUNT();

    SELECT numeroLaptop        AS laptop,
           total_liberados     AS componentes_liberados,
           destino_componentes AS estado_destino,
           total_mermados      AS mermados_conservados,
           total_cerrados      AS ensamblajes_cerrados;
END$$



-- ============================================================
-- 2. sp_Cancelar_Orden_Produccion
-- ============================================================
--
-- Objetivo : Cancelar una orden y dejar la planta consistente: el material que
--            tenía apartado vuelve al inventario y las laptops a medias se dan
--            por perdidas.
--
-- Parámetros:
--   folioOrden  Folio de la orden a cancelar.
--
-- Qué hace, en orden:
--   1. Suelta los componentes de las laptops NO terminadas de esa orden
--      (Registrada / En Ensamblaje) y cierra sus ensamblajes.
--   2. Pasa esas laptops a Rechazada.
--   3. Pasa la orden a Cancelada.
--
-- Qué NO toca:
--   - Las laptops Aprobadas y Embaladas. Ya pasaron calidad y existen
--     físicamente: cancelar la orden no es razón para tirarlas.
--   - cant_producida ni cant_rechazada. Las llevan solos los triggers
--     tg_Laptop_Alta / _Cambio / _Baja, que aplican el delta de cada laptop al
--     cambiarle el estado: las que se rechazan en el paso 2 caen solas en
--     cant_rechazada, y las Aprobadas y Embaladas que se respetan no se mueven
--     de cant_producida.
--
-- Se repiten aquí los dos UPDATE de sp_Liberar_Componentes_Laptop en vez de
-- llamarlo en un bucle, por dos razones: así es un UPDATE por toda la orden en
-- lugar de N llamadas, y porque el SELECT de resumen de aquel se le devolvería
-- al cliente una vez por laptop. Si cambias la lógica de liberación, cámbiala
-- en los dos lados.
--
-- NOTA: la orden no tiene columna para el motivo de la cancelación, así que no
--   se guarda. Si lo necesitan, hay que agregarle una a orden_produccion.

CREATE PROCEDURE sp_Cancelar_Orden_Produccion(
    IN folioOrden INT
)
BEGIN
    DECLARE estado_orden      VARCHAR(8);
    DECLARE total_liberados   INT DEFAULT 0;
    DECLARE total_rechazadas  INT DEFAULT 0;
    DECLARE total_respetadas  INT DEFAULT 0;

    -- Validaciones

    SELECT estado INTO estado_orden
      FROM orden_produccion
     WHERE folio = folioOrden;

    IF estado_orden IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Cancelar_Orden_Produccion: esa orden no existe o no tiene estado';
    END IF;

    IF estado_orden = 'CANC' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Cancelar_Orden_Produccion: esa orden ya estaba cancelada';
    END IF;

    IF estado_orden = 'COMP' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Cancelar_Orden_Produccion: esa orden ya se completó, no se puede cancelar';
    END IF;

    -- Cuántas laptops terminadas se van a respetar, para reportarlo
    SELECT COUNT(*)
      INTO total_respetadas
      FROM laptop
     WHERE orden  = folioOrden
       AND estado IN ('APROV', 'EMBALA');

    -- 1. Soltar los componentes de las laptops no terminadas
    UPDATE componente c
      JOIN registro_ensamblaje re ON re.numero = c.registro_ensamblaje
      JOIN laptop             l  ON l.numero  = re.laptop
       SET c.estado              = 'EDC001',
           c.registro_ensamblaje = NULL
     WHERE l.orden  = folioOrden
       AND l.estado IN ('REGIS', 'PENSAM')
       AND (c.estado IS NULL OR c.estado <> 'EDC004');

    SET total_liberados = ROW_COUNT();

    UPDATE registro_ensamblaje re
      JOIN laptop l ON l.numero = re.laptop
       SET re.fecha_fin = CURDATE(),
           re.hora_fin  = CURTIME()
     WHERE l.orden       = folioOrden
       AND l.estado      IN ('REGIS', 'PENSAM')
       AND re.fecha_fin  IS NULL;

    -- 2. Las laptops a medias se dan por perdidas
    UPDATE laptop
       SET estado = 'RECHA'
     WHERE orden  = folioOrden
       AND estado IN ('REGIS', 'PENSAM');

    SET total_rechazadas = ROW_COUNT();

    -- 3. La orden queda cancelada
    UPDATE orden_produccion
       SET estado = 'CANC'
     WHERE folio  = folioOrden;

    SELECT folioOrden       AS folio,
           total_rechazadas AS laptops_rechazadas,
           total_respetadas AS laptops_respetadas,
           total_liberados  AS componentes_liberados;
END$$



-- ============================================================
-- 3. sp_Iniciar_Ensamblaje_Orden
-- ============================================================
--
-- Objetivo : Dar de alta de un jalón las laptops que le faltan a una orden
--            para llegar a su cantidad planificada.
--
-- Parámetros:
--   folioOrden  Folio de la orden.
--
-- Qué hace:
--   Crea (cant_planificada - las que ya existen) laptops en estado Registrada,
--   heredando el modelo y el lote de la orden. NO abre el registro de
--   ensamblaje: eso sigue siendo laptop por laptop, cuando de verdad arranca.
--
--   La línea ya NO se pide. La tabla laptop no tiene columna de línea: dónde
--   se está armando una laptop lo dice su registro_ensamblaje, y ése se abre
--   después, unidad por unidad. Estas laptops nacen sin línea, que es lo
--   correcto: todavía no las está armando nadie.
--
-- Se puede correr dos veces sin duplicar: siempre mira cuántas faltan.
--
-- El número de serie sale provisional (TMP-0001, TMP-0002...), que es la
-- convención que ya usa el cliente. La columna es NOT NULL, así que no puede
-- quedar vacía.
--
-- La serie provisional sí se reemplaza al final: tg_Generar_Numero_Serie_Final
--   actúa cuando num_serie viene nulo, vacío O empieza con 'TMP-', así que al
--   aprobar la laptop en la última línea le pone su TP-{AAAAMMDD}-{numero}.
--   (Comprobado en el recorrido del 13-08-2026: TMP-0009 -> TP-20260813-000034.)
--
-- Los triggers que se disparan solos al insertar cada laptop:
--   tg_Arrancar_Laptop_En_Ensamblaje  → nace 'En Ensamblaje', no 'Registrada'.
--   tg_Laptop_Alta                    → si la orden estaba Pendiente pasa a En
--                                       Proceso, le aplica a la orden el delta
--                                       de la laptop (las nuevas no inflan nada:
--                                       nacen En Ensamblaje y los dos términos
--                                       valen 0) y le abre el ensamblaje de la
--                                       primera línea.

CREATE PROCEDURE sp_Iniciar_Ensamblaje_Orden(
    IN folioOrden INT
)
BEGIN
    DECLARE estado_orden       VARCHAR(8);
    DECLARE modelo_orden       VARCHAR(8);
    DECLARE lote_orden         VARCHAR(8);
    DECLARE total_planificadas INT;
    DECLARE total_existentes   INT;
    DECLARE total_faltantes    INT;
    DECLARE consecutivo_serie  INT;
    DECLARE total_creadas      INT DEFAULT 0;

    -- Validaciones

    SELECT estado, modelo_laptop, lote, IFNULL(cant_planificada, 0)
      INTO estado_orden, modelo_orden, lote_orden, total_planificadas
      FROM orden_produccion
     WHERE folio = folioOrden;

    IF estado_orden IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Iniciar_Ensamblaje_Orden: esa orden no existe o no tiene estado';
    END IF;

    IF estado_orden NOT IN ('PEND', 'PROC') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Iniciar_Ensamblaje_Orden: solo se le pueden agregar laptops a una orden Pendiente o En Proceso';
    END IF;

    IF modelo_orden IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Iniciar_Ensamblaje_Orden: la orden no tiene modelo de laptop, no se sabe qué fabricar';
    END IF;

    -- Cuántas faltan

    SELECT COUNT(*) INTO total_existentes FROM laptop WHERE orden = folioOrden;

    SET total_faltantes = total_planificadas - total_existentes;

    IF total_faltantes <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Iniciar_Ensamblaje_Orden: esta orden ya tiene todas las laptops que planificó';
    END IF;

    -- Desde qué consecutivo seguir con las series provisionales
    SELECT IFNULL(MAX(CAST(SUBSTRING(num_serie, 5) AS UNSIGNED)), 0)
      INTO consecutivo_serie
      FROM laptop
     WHERE num_serie LIKE 'TMP-%';

    WHILE total_creadas < total_faltantes DO

        SET consecutivo_serie = consecutivo_serie + 1;

        INSERT INTO laptop (num_serie, orden, modelo, estado, lote)
        VALUES (CONCAT('TMP-', LPAD(consecutivo_serie, 4, '0')),
                folioOrden,
                modelo_orden,
                'REGIS',
                lote_orden);

        SET total_creadas = total_creadas + 1;

    END WHILE;

    SELECT folioOrden         AS folio,
           total_creadas      AS laptops_creadas,
           total_existentes   AS laptops_previas,
           total_planificadas AS cant_planificada;
END$$


-- ============================================================
-- 4. sp_Recibir_Orden_Material
-- ============================================================
--
-- Objetivo : Convertir una orden de material en piezas físicas. Por cada
--            material de detalle_material da de alta los componentes que le
--            faltan y los deja Disponibles en el inventario de la línea.
--
-- Parámetros:
--   numeroOrdenMaterial  Número de la orden de material a recibir.
--   loteComponentes      Lote de componentes (lote_comp) con el que entran las
--                        piezas. NULL se acepta: entran sin lote.
--
-- Por qué existe: detalle_material dice "pedí 50 piezas del modelo X", pero los
--   componente físicos se capturaban de uno en uno desde el formulario del
--   supervisor. Cincuenta piezas eran cincuenta altas a mano, cada una su
--   propia transacción, y a media captura el inventario quedaba a medias.
--
-- Recepción parcial: siempre mira cuántas FALTAN por material (lo pedido menos
--   lo que ya se recibió de esa orden y ese modelo), igual que
--   sp_Iniciar_Ensamblaje_Orden. Así el proveedor puede mandar 30 de 50 hoy y
--   20 mañana, y correrlo dos veces no duplica nada.
--
-- La línea NO se pide: es la de la orden. Y se exige que la tenga, porque el
--   inventario del supervisor filtra por línea (ver Client, componentesListView)
--   y una pieza sin línea no aparecería en la pantalla de nadie.
--
-- Se inserta con un INSERT ... SELECT sobre un WITH RECURSIVE de números en vez
--   de un cursor con WHILE anidado: es un solo statement para toda la orden. La
--   técnica es la que ya usa sp_p2_surtir en DB/datos_pruebas2.sql.
--
-- El num_serie sale <orden>-<modelo>-<nnn>, con el consecutivo continuando
--   después de lo que ya existía de ese material. La columna es varchar(18) sin
--   UNIQUE, así que el formato cabe (4+1+8+1+3) y no se repite entre corridas.

CREATE PROCEDURE sp_Recibir_Orden_Material(
    IN numeroOrdenMaterial INT,
    IN loteComponentes     VARCHAR(12)
)
BEGIN
    DECLARE linea_orden        VARCHAR(8);
    DECLARE recepcion_fecha    DATETIME DEFAULT NULL;
    DECLARE orden_existe       INT;
    DECLARE lote_existe        INT;
    DECLARE total_materiales   INT DEFAULT 0;
    DECLARE total_faltantes    INT DEFAULT 0;
    DECLARE total_previos      INT DEFAULT 0;
    DECLARE total_creados      INT DEFAULT 0;
    DECLARE total_pendientes   INT DEFAULT 0;

    -- Validaciones

    SELECT COUNT(*), MAX(linea)
      INTO orden_existe, linea_orden
      FROM orden_material
     WHERE numero = numeroOrdenMaterial;

    IF orden_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Recibir_Orden_Material: Esa orden de material no existe';
    END IF;

    SELECT
        recepcion into recepcion_fecha
    from orden_material
    where numero = numeroOrdenMaterial;

    IF recepcion_fecha is not NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Recibir_Orden_Material: Esa orden de material ya se recibió';
    END IF;

    IF linea_orden IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Recibir_Orden_Material: La orden no tiene línea, las piezas no aparecerían en el inventario de nadie';
    END IF;

    SELECT COUNT(*) INTO total_materiales
      FROM detalle_material
     WHERE orden = numeroOrdenMaterial;

    IF total_materiales = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Recibir_Orden_Material: Esa orden no tiene materiales que recibir';
    END IF;

    -- El lote es opcional, pero si viene tiene que existir.
    IF loteComponentes IS NOT NULL THEN

        SELECT COUNT(*) INTO lote_existe FROM lote_comp WHERE codigo = loteComponentes;

        IF lote_existe = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error sp_Recibir_Orden_Material: Ese lote de componentes no existe';
        END IF;

    END IF;

    -- Qué falta por recibir

    SELECT IFNULL(SUM(GREATEST(IFNULL(dm.cantidad, 0) - IFNULL(recibido.piezas, 0), 0)), 0),
           IFNULL(SUM(IFNULL(recibido.piezas, 0)), 0)
      INTO total_faltantes, total_previos
      FROM detalle_material dm
      LEFT JOIN (SELECT modelo, COUNT(*) AS piezas
                   FROM componente
                  WHERE orden_material = numeroOrdenMaterial
                  GROUP BY modelo) AS recibido
             ON recibido.modelo = dm.modelo
     WHERE dm.orden = numeroOrdenMaterial;

    IF total_faltantes = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error sp_Recibir_Orden_Material: Esa orden de material ya se recibió completa';
    END IF;

    -- Alta de las piezas
    --
    -- La CTE de números llega hasta el material más grande que falte y el JOIN
    -- recorta por material con n.i <= por_recibir, así una sola CTE sirve para
    -- todos.
    --
    -- El consecutivo de la serie sale del MÁXIMO que ya exista de ese material,
    -- no del conteo: si a una orden ya recibida le borraron piezas de en medio,
    -- contar daría números que ya están usados. Las series que no traen el
    -- formato <orden>-<modelo>-<nnn> (las de los datos de prueba, por ejemplo)
    -- caen en 0 al castear, así que no estorban.


    INSERT INTO componente (num_serie, descripcion, linea, orden_material,
                            modelo, lote, estado, registro_ensamblaje)
    WITH RECURSIVE n(i) AS (
        SELECT 1
        UNION ALL
        SELECT i + 1 FROM n WHERE i < total_faltantes
    ),
    faltan AS (
        SELECT dm.modelo                                        AS modelo,
               IFNULL(recibido.consecutivo, 0)                  AS desde,
               GREATEST(IFNULL(dm.cantidad, 0)
                        - IFNULL(recibido.piezas, 0), 0)        AS por_recibir
          FROM detalle_material dm
          LEFT JOIN (SELECT modelo,
                            COUNT(*) AS piezas,
                            MAX(CAST(SUBSTRING_INDEX(num_serie, '-', -1) AS UNSIGNED))
                                     AS consecutivo
                       FROM componente
                      WHERE orden_material = numeroOrdenMaterial
                      GROUP BY modelo) AS recibido
                 ON recibido.modelo = dm.modelo
         WHERE dm.orden = numeroOrdenMaterial
    )
    SELECT CONCAT(numeroOrdenMaterial, '-', f.modelo, '-',
                  LPAD(f.desde + n.i, 3, '0')),
           mc.nombre,
           linea_orden,
           numeroOrdenMaterial,
           f.modelo,
           loteComponentes,
           'EDC001',
           NULL
      FROM faltan f
      JOIN n  ON n.i <= f.por_recibir
      JOIN modelo_componente mc ON mc.codigo = f.modelo
     ORDER BY f.modelo, n.i;

    SET total_creados = ROW_COUNT();

    SELECT IFNULL(SUM(GREATEST(IFNULL(dm.cantidad, 0) - IFNULL(recibido.piezas, 0), 0)), 0)
      INTO total_pendientes
      FROM detalle_material dm
      LEFT JOIN (SELECT modelo, COUNT(*) AS piezas
                   FROM componente
                  WHERE orden_material = numeroOrdenMaterial
                  GROUP BY modelo) AS recibido
             ON recibido.modelo = dm.modelo
     WHERE dm.orden = numeroOrdenMaterial;

    IF total_pendientes = 0 THEN
        UPDATE orden_material
           SET recepcion = NOW()
         WHERE numero = numeroOrdenMaterial;
    END IF;

    SELECT numeroOrdenMaterial AS orden,
           linea_orden         AS linea,
           loteComponentes     AS lote,
           total_materiales    AS materiales,
           total_creados       AS componentes_creados,
           total_previos       AS componentes_previos,
           total_pendientes    AS componentes_pendientes;
END$$


-- ============================================================
-- 5. sp_Dashboard_Resumen
-- ============================================================
--
-- Objetivo : Devolver en un solo renglón los números del dashboard de
--            administrador para un rango de fechas.
--
-- Parámetros:
--   fechaDesde  Primer día del rango. NULL = desde que existe la planta.
--   fechaHasta  Último día del rango. NULL = hasta hoy.
--
-- ADVERTENCIA — éste no es como los otros cuatro
-- --------------------------------------------
-- Los de arriba existen porque tocan muchas filas de varias tablas y tienen
-- que pasar o no pasar completas. Éste no escribe nada: solamente lee. No hay
-- transacción que proteger ni atomicidad que ganar.
--
-- El dashboard NO lo usa. El panel de administrador se sirve de las vistas
-- vista_dash_* (DB/vistas.sql), que Django mapea con modelos managed=False y
-- que la API puede filtrar, ordenar y paginar como cualquier otra consulta.
-- Un procedimiento devuelve un conjunto de tuplas suelto: se lee con
-- cursor.callproc(), no pasa por un serializer y no se le puede encadenar nada.
--
-- Entonces, ¿para qué está? Para tener a la mano la versión "un solo CALL con
-- el rango como parámetro", que es lo que una vista no puede hacer (en MySQL
-- las vistas no reciben parámetros). Sirve para demostrarlo y para consultarlo
-- desde la consola:
--
--     CALL sp_Dashboard_Resumen('2026-07-01', '2026-07-31');
--     CALL sp_Dashboard_Resumen(NULL, NULL);   -- todo el histórico
--
-- Si algún día se decide que el dashboard corra sobre procedimientos, éste es
-- el punto de partida; mientras tanto, la fuente de verdad son las vistas.
--
-- Qué cuenta como producida: la laptop embalada, igual que en las vistas y
-- que en tg_Registrar_Embalaje.

CREATE PROCEDURE sp_Dashboard_Resumen(
    IN fechaDesde DATE,
    IN fechaHasta DATE
)
BEGIN
    -- Rango abierto por cualquiera de los dos lados. '1000-01-01' es el
    DECLARE desde DATE DEFAULT IFNULL(fechaDesde, '1000-01-01');
    DECLARE hasta DATE DEFAULT IFNULL(fechaHasta, CURDATE());

    SELECT
        desde AS rango_desde,
        hasta AS rango_hasta,

        (SELECT IFNULL(SUM(total), 0)
           FROM vista_dash_produccion_diaria
          WHERE fecha BETWEEN desde AND hasta)          AS producidas,

        (SELECT IFNULL(SUM(total), 0)
           FROM vista_dash_calidad_diaria
          WHERE fecha BETWEEN desde AND hasta)          AS inspecciones,

        (SELECT IFNULL(SUM(aprobadas), 0)
           FROM vista_dash_calidad_diaria
          WHERE fecha BETWEEN desde AND hasta)          AS inspecciones_aprobadas,

        (SELECT IFNULL(SUM(rechazadas), 0)
           FROM vista_dash_calidad_diaria
          WHERE fecha BETWEEN desde AND hasta)          AS inspecciones_rechazadas,

        (SELECT IFNULL(SUM(total), 0)
           FROM vista_dash_paros_diaria
          WHERE fecha BETWEEN desde AND hasta)          AS paros,

        (SELECT IFNULL(SUM(minutos), 0)
           FROM vista_dash_paros_diaria
          WHERE fecha BETWEEN desde AND hasta)          AS paros_minutos,

        (SELECT COUNT(*)
           FROM orden_produccion
          WHERE fecha BETWEEN desde AND hasta)          AS ordenes_creadas;
END$$


DELIMITER ;


CALL sp_Dashboard_Resumen('2026-08-14','2026-08-14'); CALL sp_Dashboard_Resumen('2026-07-16','2026-08-14'); CALL sp_Dashboard_Resumen(NULL,NULL);