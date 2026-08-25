-- Active: 1783038914702@@localhost@3306@cuatro

-- TRACEX — Datos de prueba 2 (volumen)
-- Version: 2026-08-06
--
-- Objetivo : Meterle carga al sistema. Más órdenes, más laptops, historia de
--            varios días y laptops en todos los puntos del proceso, para probar
--            listados, filtros, reportes y el flujo de calidad con datos que se
--            parezcan a los de una planta trabajando.
--
-- REQUISITOS (ejecutar en este orden ANTES que este archivo):
--   1) estructura.sql
--   2) datos.sql
--   3) triggers.sql
--   4) datos_pruebas.sql
--
-- SE SUMA, NO REEMPLAZA. Este archivo NO limpia nada: se apila sobre lo que ya
-- dejó datos_pruebas.sql. Todos sus números de serie llevan prefijo propio
-- (P2-, TMP-P2-) para no chocar con los de aquel.
--
-- ----------------------------------------------------------------------------
-- CÓMO ESTÁ ESCRITO
--
-- Nada de estados escritos a mano. Una laptop llega a Aprobada porque pasó sus
-- cuatro inspecciones, y una orden llega a Completada porque se embalaron todas
-- sus laptops. Los triggers hacen el trabajo, igual que cuando alguien usa el
-- programa. Por eso aquí solo se dan de alta las laptops y se llama a los
-- procedimientos que recorren el proceso.
--
-- Los seis procedimientos de abajo son ANDAMIO: existen solo mientras corre este
-- archivo y se borran al final. No son parte del sistema.
-- ============================================================================

USE cuatro;

-- Marca de agua: todo lo que este archivo agregue queda por encima de estos
-- números. Sirve para acotar los ajustes de fecha del final sin tocar los datos
-- que ya existían.
SET @base_laptop := (SELECT IFNULL(MAX(numero), 0) FROM laptop);
SET @base_comp   := (SELECT IFNULL(MAX(numero), 0) FROM componente);


-- ============================================================================
--  ANDAMIO — procedimientos auxiliares
-- ============================================================================

DROP PROCEDURE IF EXISTS sp_p2_surtir;
DROP PROCEDURE IF EXISTS sp_p2_montar;
DROP PROCEDURE IF EXISTS sp_p2_inspeccionar;
DROP PROCEDURE IF EXISTS sp_p2_avanzar_hasta;
DROP PROCEDURE IF EXISTS sp_p2_terminar;
DROP PROCEDURE IF EXISTS sp_p2_rechazar;
DROP PROCEDURE IF EXISTS sp_p2_embalar;

DELIMITER $$

-- ----------------------------------------------------------------------------
-- sp_p2_surtir — mete N piezas de CADA modelo de componente, cada una en la
-- línea que la instala. El mapa tipo -> línea es el de las estaciones (ver el
-- comentario de tipo_comp en datos.sql); si una pieza cayera en otra línea, esa
-- línea la vería como suya en el checklist de revisión.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_p2_surtir(IN p_unidades INT)
BEGIN
    INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje)
    WITH RECURSIVE n(i) AS (
        SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < p_unidades
    )
    SELECT CONCAT('P2-', mc.codigo, '-', LPAD(n.i, 3, '0')),
           mc.nombre,
           CASE mc.tipo_componente
               WHEN 'TC012' THEN 'LIN001'   -- Chasis Superior
               WHEN 'TC008' THEN 'LIN001'   -- Touchpad
               WHEN 'TC007' THEN 'LIN001'   -- Teclado
               WHEN 'TC015' THEN 'LIN001'   -- Altavoces
               WHEN 'TC014' THEN 'LIN001'   -- Conector de Carga
               WHEN 'TC004' THEN 'LIN002'   -- Tarjeta Madre
               WHEN 'TC001' THEN 'LIN002'   -- Procesador
               WHEN 'TC002' THEN 'LIN002'   -- Memoria RAM
               WHEN 'TC003' THEN 'LIN003'   -- Almacenamiento SSD
               WHEN 'TC010' THEN 'LIN003'   -- Tarjeta de Red
               WHEN 'TC011' THEN 'LIN003'   -- Disipador
               WHEN 'TC005' THEN 'LIN004'   -- Pantalla
               WHEN 'TC009' THEN 'LIN004'   -- Cámara Web
               WHEN 'TC006' THEN 'LIN004'   -- Batería
               WHEN 'TC013' THEN 'LIN004'   -- Chasis Inferior
           END,
           mc.codigo,
           -- El lote se asigna hasta la sección 7, cuando ya existen todas las
           -- piezas y se puede cortar cada 20 por modelo de una sola pasada.
           NULL,
           'EDC001',
           NULL
      FROM modelo_componente mc, n;
END$$


-- ----------------------------------------------------------------------------
-- sp_p2_montar — pone en la laptop las piezas que instala la línea donde está
-- parada, tomándolas del stock libre DE ESA LÍNEA.
--
-- Respeta la capacidad por tipo del BOM y descuenta lo que ya trae puesto de
-- líneas anteriores, que es justo lo que hace la pantalla de revisión.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_p2_montar(IN p_laptop INT)
BEGIN
    DECLARE v_reg    INT DEFAULT NULL;
    DECLARE v_linea  VARCHAR(8) DEFAULT NULL;
    DECLARE v_modelo VARCHAR(8) DEFAULT NULL;

    SELECT re.numero, re.linea INTO v_reg, v_linea
      FROM registro_ensamblaje re
     WHERE re.laptop = p_laptop AND re.fecha_fin IS NULL
     LIMIT 1;

    IF v_reg IS NOT NULL THEN

        SELECT modelo INTO v_modelo FROM laptop WHERE numero = p_laptop;

        -- Cuántas piezas de cada tipo le faltan todavía a esta laptop.
        DROP TEMPORARY TABLE IF EXISTS tmp_p2_cupo;
        CREATE TEMPORARY TABLE tmp_p2_cupo AS
        SELECT mc.tipo_componente AS tipo,
               MAX(mlc.capacidad) - IFNULL((
                   SELECT COUNT(*)
                     FROM componente c
                     JOIN registro_ensamblaje r2  ON r2.numero  = c.registro_ensamblaje
                     JOIN modelo_componente   mc2 ON mc2.codigo = c.modelo
                    WHERE r2.laptop = p_laptop
                      AND mc2.tipo_componente = mc.tipo_componente
                      AND (c.estado IS NULL OR c.estado <> 'EDC004')
               ), 0) AS cupo
          FROM modelo_laptop_componente mlc
          JOIN modelo_componente mc ON mc.codigo = mlc.modelo_componente
         WHERE mlc.modelo_laptop = v_modelo
         GROUP BY mc.tipo_componente;

        -- De lo libre en esta línea, se aparta exactamente ese cupo por tipo.
        DROP TEMPORARY TABLE IF EXISTS tmp_p2_tomar;
        CREATE TEMPORARY TABLE tmp_p2_tomar AS
        SELECT x.numero
          FROM (
                SELECT c.numero,
                       mc.tipo_componente AS tipo,
                       ROW_NUMBER() OVER (PARTITION BY mc.tipo_componente
                                              ORDER BY c.numero) AS rn
                  FROM componente c
                  JOIN modelo_componente mc ON mc.codigo = c.modelo
                 WHERE c.estado = 'EDC001'
                   AND c.registro_ensamblaje IS NULL
                   AND c.linea = v_linea
                   AND mc.codigo IN (SELECT modelo_componente
                                       FROM modelo_laptop_componente
                                      WHERE modelo_laptop = v_modelo)
               ) x
          JOIN tmp_p2_cupo k ON k.tipo = x.tipo AND x.rn <= k.cupo
         WHERE k.cupo > 0;

        UPDATE componente
           SET registro_ensamblaje = v_reg,
               estado = 'EDC002'
         WHERE numero IN (SELECT numero FROM tmp_p2_tomar);

        DROP TEMPORARY TABLE IF EXISTS tmp_p2_cupo;
        DROP TEMPORARY TABLE IF EXISTS tmp_p2_tomar;
    END IF;
END$$


-- ----------------------------------------------------------------------------
-- sp_p2_inspeccionar — registra la inspección de la línea donde está la laptop,
-- a nombre del OPCALI de esa línea.
--
-- No hace nada más: cerrar el ensamblaje, pasar a la línea siguiente, aprobar o
-- rechazar lo resuelve tg_Actualizar_Estado_Laptop_Inspeccion_Calidad. Eso es a
-- propósito, para que estos datos pasen por el mismo camino que la aplicación.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_p2_inspeccionar(IN p_laptop INT, IN p_resultado TINYINT, IN p_obs VARCHAR(256))
BEGIN
    DECLARE v_linea VARCHAR(8) DEFAULT NULL;
    DECLARE v_emp   INT DEFAULT NULL;

    SELECT linea INTO v_linea
      FROM registro_ensamblaje
     WHERE laptop = p_laptop AND fecha_fin IS NULL
     LIMIT 1;

    IF v_linea IS NOT NULL THEN
        SELECT el.empleado INTO v_emp
          FROM empleado_linea el
          JOIN empleado e ON e.numero = el.empleado
         WHERE el.linea = v_linea
           AND el.fecha_fin IS NULL
           AND e.rol = 'OPCALI'
         LIMIT 1;

        INSERT INTO inspeccion_calidad
               (resultado, observaciones, fecha, hora, laptop, empleado, linea)
        VALUES (p_resultado, p_obs, CURDATE(), CURTIME(), p_laptop, v_emp, v_linea);
    END IF;
END$$


-- ----------------------------------------------------------------------------
-- sp_p2_avanzar_hasta — recorre líneas hasta quedarse parada en la que se pide,
-- con sus piezas puestas y sin inspeccionar. Es la laptop que el inspector de
-- esa línea se va a encontrar pendiente.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_p2_avanzar_hasta(IN p_laptop INT, IN p_linea VARCHAR(8))
BEGIN
    DECLARE v_actual  VARCHAR(8) DEFAULT NULL;
    DECLARE v_guardia INT DEFAULT 0;

    SELECT linea INTO v_actual FROM registro_ensamblaje
     WHERE laptop = p_laptop AND fecha_fin IS NULL LIMIT 1;

    -- La guardia corta por si los datos de línea.siguiente quedaran mal: mejor
    -- una laptop a medias que un bucle infinito cargando el archivo.
    WHILE v_actual IS NOT NULL AND v_actual <> p_linea AND v_guardia < 10 DO
        CALL sp_p2_montar(p_laptop);
        CALL sp_p2_inspeccionar(p_laptop, 1, 'Conforme, pasa a la siguiente línea');
        SET v_guardia = v_guardia + 1;
        SET v_actual = NULL;
        SELECT linea INTO v_actual FROM registro_ensamblaje
         WHERE laptop = p_laptop AND fecha_fin IS NULL LIMIT 1;
    END WHILE;

    CALL sp_p2_montar(p_laptop);
END$$


-- ----------------------------------------------------------------------------
-- sp_p2_terminar — la lleva por todas las líneas aprobando. Al aprobar la
-- última, el trigger la deja Aprobada y le genera el número de serie definitivo.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_p2_terminar(IN p_laptop INT)
BEGIN
    DECLARE v_abiertos INT DEFAULT 1;
    DECLARE v_guardia  INT DEFAULT 0;

    WHILE v_abiertos > 0 AND v_guardia < 10 DO
        CALL sp_p2_montar(p_laptop);
        CALL sp_p2_inspeccionar(p_laptop, 1, 'Conforme');
        SET v_guardia = v_guardia + 1;
        SELECT COUNT(*) INTO v_abiertos FROM registro_ensamblaje
         WHERE laptop = p_laptop AND fecha_fin IS NULL;
    END WHILE;
END$$


-- ----------------------------------------------------------------------------
-- sp_p2_rechazar — la reprueba en la línea donde va, culpando a una pieza del
-- TIPO que se le indique.
--
-- El tipo se pasa a propósito en vez de tomar "la última montada": el stock se
-- surte modelo por modelo, así que la pieza de número más alto siempre era la
-- del último modelo del catálogo y todas las observaciones acababan culpando a
-- los altavoces, dijera lo que dijera el texto.
--
-- El orden de las tres operaciones importa y es el mismo que sigue la pantalla:
-- primero la inspección (el renglón de detalle la referencia por llave foránea),
-- luego el detalle mientras la pieza sigue montada, y hasta el final se desmonta
-- y se marca dañada.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_p2_rechazar(IN p_laptop INT, IN p_tipo VARCHAR(8), IN p_obs VARCHAR(256))
BEGIN
    DECLARE v_insp INT DEFAULT NULL;
    DECLARE v_comp INT DEFAULT NULL;

    CALL sp_p2_montar(p_laptop);

    -- La pieza que se va a culpar: una del tipo señalado, de las que trae
    -- puestas esta laptop.
    SELECT c.numero INTO v_comp
      FROM componente c
      JOIN registro_ensamblaje r  ON r.numero  = c.registro_ensamblaje
      JOIN modelo_componente   mc ON mc.codigo = c.modelo
     WHERE r.laptop = p_laptop
       AND c.estado = 'EDC002'
       AND mc.tipo_componente = p_tipo
     LIMIT 1;

    CALL sp_p2_inspeccionar(p_laptop, 0, p_obs);

    SELECT MAX(numero) INTO v_insp FROM inspeccion_calidad WHERE laptop = p_laptop;

    IF v_comp IS NOT NULL AND v_insp IS NOT NULL THEN
        INSERT INTO detalle_inspeccion (inspeccion, componente, observacion)
        VALUES (v_insp, v_comp, p_obs);

        UPDATE componente
           SET estado = 'EDC003', registro_ensamblaje = NULL
         WHERE numero = v_comp;
    END IF;
END$$


-- ----------------------------------------------------------------------------
-- sp_p2_embalar — embala una laptop aprobada. El trigger la pasa a Embalada y,
-- si con ella se completan las planificadas, cierra la orden.
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_p2_embalar(IN p_laptop INT, IN p_tipo VARCHAR(8))
BEGIN
    INSERT INTO registro_embalaje (fecha, hora, laptop, tipo)
    VALUES (CURDATE(), CURTIME(), p_laptop, p_tipo);
END$$

DELIMITER ;


-- ============================================================================
--  1. SURTIR MATERIAL
--
--  40 piezas de cada modelo. Con ~25 laptops nuevas se consumen unas 425, así
--  que queda material libre de sobra para seguir probando el checklist.
-- ============================================================================
CALL sp_p2_surtir(40);


-- ============================================================================
--  2. ÓRDENES DE PRODUCCIÓN Y SU RECORRIDO
--
--  Se dan de alta en PEND. Los triggers las mueven: a PROC en cuanto se les
--  registra una laptop, y a COMP cuando se embalan todas las planificadas.
--
--  cant_producida y cant_rechazada entran en cero: las dos las lleva el
--  trigger de laptop conforme avanza el recorrido. Al final del archivo, las
--  órdenes C y D son las que quedan con cant_rechazada = 1 (una unidad
--  descartada cada una).
-- ============================================================================

-- ---------------------------------------------------------------- ORDEN A
-- 3 planificadas, las 3 terminadas y embaladas -> queda COMPLETADA.
INSERT INTO orden_produccion (fecha, hora, modelo_laptop, cant_planificada, cant_producida, cant_rechazada, estado, lote) VALUES
('2026-08-01', '07:00:00', 'ML001', 3, 0, 0, 'PEND', 'LOT2026A');
SET @ordA := LAST_INSERT_ID();

INSERT INTO laptop (num_serie, orden, modelo, estado, lote) VALUES
('TMP-P2-A1', @ordA, 'ML001', 'REGIS', 'LOT2026A'),   -- terminada
('TMP-P2-A2', @ordA, 'ML001', 'REGIS', 'LOT2026A'),   -- terminada
('TMP-P2-A3', @ordA, 'ML001', 'REGIS', 'LOT2026A');   -- terminada

SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-A1');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE001');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-A2');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE002');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-A3');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE001');


-- ---------------------------------------------------------------- ORDEN B
-- 5 planificadas, 4 terminadas y embaladas, 1 todavía en la línea C.
-- Queda EN PROCESO con 4 de 5. Es el caso que se pidió explícitamente.
INSERT INTO orden_produccion (fecha, hora, modelo_laptop, cant_planificada, cant_producida, cant_rechazada, estado, lote) VALUES
('2026-08-02', '07:00:00', 'ML001', 5, 0, 0, 'PEND', 'LOT2026A');
SET @ordB := LAST_INSERT_ID();

INSERT INTO laptop (num_serie, orden, modelo, estado, lote) VALUES
('TMP-P2-B1', @ordB, 'ML001', 'REGIS', 'LOT2026A'),   -- terminada
('TMP-P2-B2', @ordB, 'ML001', 'REGIS', 'LOT2026A'),   -- terminada
('TMP-P2-B3', @ordB, 'ML001', 'REGIS', 'LOT2026A'),   -- terminada
('TMP-P2-B4', @ordB, 'ML001', 'REGIS', 'LOT2026A'),   -- terminada
('TMP-P2-B5', @ordB, 'ML001', 'REGIS', 'LOT2026A');   -- en ensamblaje (C)

SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-B1');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE001');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-B2');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE003');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-B3');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE001');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-B4');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE004');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-B5');
CALL sp_p2_avanzar_hasta(@l, 'LIN003');


-- ---------------------------------------------------------------- ORDEN C
-- 6 planificadas, repartidas por las cuatro líneas para que el flujo de calidad
-- tenga trabajo pendiente en todas, más una rechazada.
INSERT INTO orden_produccion (fecha, hora, modelo_laptop, cant_planificada, cant_producida, cant_rechazada, estado, lote) VALUES
('2026-08-03', '07:00:00', 'ML001', 6, 0, 0, 'PEND', 'LOT2026B');
SET @ordC := LAST_INSERT_ID();

INSERT INTO laptop (num_serie, orden, modelo, estado, lote) VALUES
('TMP-P2-C1', @ordC, 'ML001', 'REGIS', 'LOT2026B'),   -- parada en A
('TMP-P2-C2', @ordC, 'ML001', 'REGIS', 'LOT2026B'),   -- parada en B
('TMP-P2-C3', @ordC, 'ML001', 'REGIS', 'LOT2026B'),   -- parada en C
('TMP-P2-C4', @ordC, 'ML001', 'REGIS', 'LOT2026B'),   -- parada en D
('TMP-P2-C5', @ordC, 'ML001', 'REGIS', 'LOT2026B'),   -- rechazada
('TMP-P2-C6', @ordC, 'ML001', 'REGIS', 'LOT2026B');   -- terminada

SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-C1');
CALL sp_p2_avanzar_hasta(@l, 'LIN001');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-C2');
CALL sp_p2_avanzar_hasta(@l, 'LIN002');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-C3');
CALL sp_p2_avanzar_hasta(@l, 'LIN003');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-C4');
CALL sp_p2_avanzar_hasta(@l, 'LIN004');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-C5');
CALL sp_p2_avanzar_hasta(@l, 'LIN002');
CALL sp_p2_rechazar(@l, 'TC004', 'Tarjeta madre sin video, se descarta el equipo');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-C6');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE002');


-- ---------------------------------------------------------------- ORDEN D
-- 4 planificadas: 2 embaladas, 1 rechazada en la línea D (casi al final) y 1
-- parada en B. Sirve para ver una orden con merma.
INSERT INTO orden_produccion (fecha, hora, modelo_laptop, cant_planificada, cant_producida, cant_rechazada, estado, lote) VALUES
('2026-08-03', '14:00:00', 'ML001', 4, 0, 0, 'PEND', 'LOT2026B');
SET @ordD := LAST_INSERT_ID();

INSERT INTO laptop (num_serie, orden, modelo, estado, lote) VALUES
('TMP-P2-D1', @ordD, 'ML001', 'REGIS', 'LOT2026B'),   -- terminada
('TMP-P2-D2', @ordD, 'ML001', 'REGIS', 'LOT2026B'),   -- terminada
('TMP-P2-D3', @ordD, 'ML001', 'REGIS', 'LOT2026B'),   -- rechazada en D
('TMP-P2-D4', @ordD, 'ML001', 'REGIS', 'LOT2026B');   -- parada en B

SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-D1');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE001');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-D2');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE003');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-D3');
CALL sp_p2_avanzar_hasta(@l, 'LIN004');
CALL sp_p2_rechazar(@l, 'TC005', 'Pantalla con pixeles muertos, se descarta el equipo');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-D4');
CALL sp_p2_avanzar_hasta(@l, 'LIN002');


-- ---------------------------------------------------------------- ORDEN E
-- Cancelada a media producción: alcanzó a arrancar una laptop antes de que la
-- cancelaran, y esa se quedó parada en la línea A.
INSERT INTO orden_produccion (fecha, hora, modelo_laptop, cant_planificada, cant_producida, cant_rechazada, estado, lote) VALUES
('2026-08-04', '07:30:00', 'ML001', 3, 0, 0, 'PEND', 'LOT2026B');
SET @ordE := LAST_INSERT_ID();

INSERT INTO laptop (num_serie, orden, modelo, estado, lote) VALUES
('TMP-P2-E1', @ordE, 'ML001', 'REGIS', 'LOT2026B');   -- de orden cancelada

UPDATE orden_produccion SET estado = 'CANC' WHERE folio = @ordE;


-- ---------------------------------------------------------------- ORDEN F
-- Recién capturada, sin laptops: es la única que se queda en PENDIENTE.
INSERT INTO orden_produccion (fecha, hora, modelo_laptop, cant_planificada, cant_producida, cant_rechazada, estado, lote) VALUES
('2026-08-05', '07:00:00', 'ML001', 5, 0, 0, 'PEND', 'LOT2026B');


-- ---------------------------------------------------------------- ORDEN G
-- 4 planificadas: 3 ya aprobadas pero SIN embalar todavía, y 1 en la línea D.
-- Deja trabajo pendiente en la línea de embalaje.
INSERT INTO orden_produccion (fecha, hora, modelo_laptop, cant_planificada, cant_producida, cant_rechazada, estado, lote) VALUES
('2026-08-05', '09:00:00', 'ML001', 4, 0, 0, 'PEND', 'LOT2026A');
SET @ordG := LAST_INSERT_ID();

INSERT INTO laptop (num_serie, orden, modelo, estado, lote) VALUES
('TMP-P2-G1', @ordG, 'ML001', 'REGIS', 'LOT2026A'),   -- aprobada, por embalar
('TMP-P2-G2', @ordG, 'ML001', 'REGIS', 'LOT2026A'),   -- aprobada, por embalar
('TMP-P2-G3', @ordG, 'ML001', 'REGIS', 'LOT2026A'),   -- aprobada, por embalar
('TMP-P2-G4', @ordG, 'ML001', 'REGIS', 'LOT2026A');   -- parada en D

SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-G1'); CALL sp_p2_terminar(@l);
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-G2'); CALL sp_p2_terminar(@l);
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-G3'); CALL sp_p2_terminar(@l);
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-G4');
CALL sp_p2_avanzar_hasta(@l, 'LIN004');


-- ---------------------------------------------------------------- ORDEN H
-- Chica y completada: 2 de 2.
INSERT INTO orden_produccion (fecha, hora, modelo_laptop, cant_planificada, cant_producida, cant_rechazada, estado, lote) VALUES
('2026-08-06', '08:00:00', 'ML001', 2, 0, 0, 'PEND', 'LOT2026A');
SET @ordH := LAST_INSERT_ID();

INSERT INTO laptop (num_serie, orden, modelo, estado, lote) VALUES
('TMP-P2-H1', @ordH, 'ML001', 'REGIS', 'LOT2026A'),   -- terminada
('TMP-P2-H2', @ordH, 'ML001', 'REGIS', 'LOT2026A');   -- terminada

SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-H1');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE004');
SET @l := (SELECT numero FROM laptop WHERE num_serie = 'TMP-P2-H2');
CALL sp_p2_terminar(@l); CALL sp_p2_embalar(@l, 'TE002');


-- ============================================================================
--  3. COMPONENTES SUELTOS EN OTROS ESTADOS
--
--  El recorrido de arriba ya deja piezas En Uso y Dañadas (las que reprobaron
--  una inspección). Faltan las mermadas y unas cuantas dañadas de recepción,
--  que nunca llegaron a montarse, para que los filtros por estado tengan de
--  todo en cada línea.
-- ============================================================================

-- Dañadas al recibirlas: se detectaron en el propio almacén de la línea.
UPDATE componente
   SET estado = 'EDC003', descripcion = CONCAT(descripcion, ' (dañado en recepción)')
 WHERE numero > @base_comp
   AND estado = 'EDC001'
   AND registro_ensamblaje IS NULL
   AND num_serie LIKE 'P2-%-039';

-- Mermadas: se perdieron o se descartaron sin instalarse.
UPDATE componente
   SET estado = 'EDC004', descripcion = CONCAT(descripcion, ' (mermado en almacén)')
 WHERE numero > @base_comp
   AND estado = 'EDC001'
   AND registro_ensamblaje IS NULL
   AND num_serie LIKE 'P2-%-040';


-- ============================================================================
--  4. ÓRDENES DE MATERIAL
--
--  Una por línea de ensamblaje, pidiendo exactamente los modelos que instalan
--  sus estaciones. El reparto es el mismo que el del stock: una línea nunca
--  pide algo que no monta.
-- ============================================================================
INSERT INTO orden_material (solicitud, necesitada, linea) VALUES
('2026-08-04 06:30:00', '2026-08-06 07:00:00', 'LIN001'),
('2026-08-04 06:45:00', '2026-08-06 07:00:00', 'LIN002'),
('2026-08-04 07:00:00', '2026-08-06 14:00:00', 'LIN003'),
('2026-08-04 07:15:00', '2026-08-06 14:00:00', 'LIN004');

-- Los renglones se derivan del mapa tipo -> línea, así no hay forma de que se
-- descuadren con el stock de arriba.
INSERT INTO detalle_material (orden, modelo, cantidad)
SELECT om.numero, mc.codigo, 30
  FROM orden_material om
  JOIN modelo_componente mc
    ON om.linea = CASE mc.tipo_componente
                      WHEN 'TC012' THEN 'LIN001' WHEN 'TC008' THEN 'LIN001'
                      WHEN 'TC007' THEN 'LIN001' WHEN 'TC015' THEN 'LIN001'
                      WHEN 'TC014' THEN 'LIN001'
                      WHEN 'TC004' THEN 'LIN002' WHEN 'TC001' THEN 'LIN002'
                      WHEN 'TC002' THEN 'LIN002'
                      WHEN 'TC003' THEN 'LIN003' WHEN 'TC010' THEN 'LIN003'
                      WHEN 'TC011' THEN 'LIN003'
                      WHEN 'TC005' THEN 'LIN004' WHEN 'TC009' THEN 'LIN004'
                      WHEN 'TC006' THEN 'LIN004' WHEN 'TC013' THEN 'LIN004'
                  END
 WHERE DATE(om.solicitud) = '2026-08-04';


-- ============================================================================
--  5. PAROS DE LÍNEA
--
--  Cerrados en varios días y algunos abiertos, para que los reportes de
--  disponibilidad tengan de los dos tipos.
-- ============================================================================
INSERT INTO paro (razon, fecha_inicio, fecha_fin, hora_inicio, hora_fin, linea) VALUES
('Cambio de herramental en la estación de touchpad', '2026-08-01', '2026-08-01', '10:00:00', '10:45:00', 'LIN001'),
('Falta de tarjetas madre en línea',                 '2026-08-02', '2026-08-02', '11:20:00', '13:00:00', 'LIN002'),
('Mantenimiento preventivo del atornillador',        '2026-08-03', '2026-08-03', '08:00:00', '09:30:00', 'LIN003'),
('Calibración del equipo de prueba de video',        '2026-08-04', '2026-08-04', '15:10:00', '16:00:00', 'LIN004'),
('Falla eléctrica en el tablero de la línea',        '2026-08-05', '2026-08-05', '07:40:00', '08:25:00', 'LIN001'),
('Ajuste de la selladora de cajas',                  '2026-08-05', '2026-08-05', '12:00:00', '12:40:00', 'LIN005'),
('Espera de material de empaque',                    '2026-08-06', NULL,         '09:15:00', NULL,       'LIN005'),
('Banda transportadora detenida',                    '2026-08-06', NULL,         '10:05:00', NULL,       'LIN003');


-- ============================================================================
--  6. REPARTO DE FECHAS Y HORAS
--
--  Los triggers sellan todo con la fecha y la hora de HOY, así que sin esto las
--  25 laptops se verían producidas en el mismo instante y los reportes por
--  fecha no mostrarían nada. Se reparten hacia atrás en una semana, de forma
--  determinista según el número de laptop, y solo se tocan las de este archivo.
--
--  El desfase se aplica igual a los tres lados (ensamblaje, inspección y
--  embalaje) para que la historia de cada laptop siga siendo coherente.
-- ============================================================================

UPDATE registro_ensamblaje re
  JOIN laptop l ON l.numero = re.laptop
   SET re.fecha_inicio = re.fecha_inicio - INTERVAL MOD(l.numero, 7) DAY,
       re.fecha_fin    = re.fecha_fin    - INTERVAL MOD(l.numero, 7) DAY
 WHERE l.numero > @base_laptop;

UPDATE registro_ensamblaje re
  JOIN laptop l ON l.numero = re.laptop
  JOIN (SELECT numero,
               ROW_NUMBER() OVER (PARTITION BY laptop ORDER BY numero) AS paso
          FROM registro_ensamblaje) o ON o.numero = re.numero
   SET re.hora_inicio = SEC_TO_TIME(
           TIME_TO_SEC('06:00:00') + (MOD(l.numero, 30) * 30 + (o.paso - 1) * 45) * 60)
 WHERE l.numero > @base_laptop;

--  Y la duración: de 15 a 35 minutos, según el número de registro. Sólo para lo
--  que ya cerró; lo que sigue abierto se queda sin hora_fin, que es justo lo que
--  lo hace contar hasta la hora actual.

UPDATE registro_ensamblaje re
  JOIN laptop l ON l.numero = re.laptop
   SET re.hora_fin = re.hora_inicio + INTERVAL (15 + MOD(re.numero, 21)) MINUTE
 WHERE l.numero > @base_laptop
   AND re.fecha_fin IS NOT NULL;

UPDATE inspeccion_calidad ic
  JOIN laptop l ON l.numero = ic.laptop
   SET ic.fecha = ic.fecha - INTERVAL MOD(l.numero, 7) DAY
 WHERE l.numero > @base_laptop;

UPDATE registro_embalaje rb
  JOIN laptop l ON l.numero = rb.laptop
   SET rb.fecha = rb.fecha - INTERVAL MOD(l.numero, 7) DAY
 WHERE l.numero > @base_laptop;


-- ============================================================================
--  7. LOTES DE COMPONENTE
--
--  Un lote es lo que llegó junto del proveedor, y el proveedor surte en cajas:
--  aquí se corta cada 20 piezas DEL MISMO MODELO. El corte es por modelo y no
--  por número de componente porque una caja no trae chasis y teclados
--  revueltos.
--
--  POR QUÉ 20 Y NO 50
--  ------------------
--  Cada modelo acaba con entre 45 y 51 piezas —40 de sp_p2_surtir más las que
--  trae datos_pruebas.sql—, así que cortar cada 50 daría UN lote por modelo, y
--  tres lotes de una sola pieza para los modelos que llegan a 51. Con eso,
--  decir "el lote X salió malo" sería idéntico a decir "ese modelo salió malo":
--  el lote no aportaría nada que el modelo no dijera ya.
--
--  Cada 20 da 3 lotes por modelo, así que un lote defectuoso pega en un tercio
--  de las laptops que llevan esa pieza. Ése es el caso que hace útil la
--  trazabilidad, y es lo que empieza a distinguir vista_traza_orden_componentes
--  (DB/vistas.sql), que agrupa por lote y hasta ahora veía los mismos dos en
--  todas las órdenes.
--
--  SE HACE HASTA AQUÍ, y no al crear cada pieza, para que la regla se aplique
--  una sola vez sobre el total: así no importa en qué archivo nació cada
--  componente ni con cuántas unidades se llame a sp_p2_surtir.
--
--  Las piezas que se den de alta después, al recibir una orden de material,
--  llevan el lote que elija quien la reciba: sp_Recibir_Orden_Material no
--  inventa lotes.
-- ============================================================================

-- Los códigos quedan LC-<modelo>-<NN>: 11 caracteres, caben en el varchar(12).
-- El tope de 20 en la recursión es holgura; hoy ningún modelo pasa de 3 lotes.
INSERT INTO lote_comp (codigo, descripcion)
WITH RECURSIVE n(i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 20
),
por_modelo AS (
    SELECT modelo, CEIL(COUNT(*) / 20) AS lotes
      FROM componente
     WHERE modelo IS NOT NULL
     GROUP BY modelo
)
SELECT CONCAT('LC-', p.modelo, '-', LPAD(n.i, 2, '0')),
       CONCAT(mc.nombre, ' - lote ', LPAD(n.i, 2, '0'))
  FROM por_modelo p
  JOIN n ON n.i <= p.lotes
  JOIN modelo_componente mc ON mc.codigo = p.modelo;

-- Cada pieza a su lote según su posición dentro del modelo: las primeras 20 al
-- 01, las siguientes 20 al 02, y así. Se ordena por `numero`, que es el orden
-- en que entraron, para que las piezas viejas —las que datos_pruebas.sql ya
-- dejó montadas en laptops— caigan en los lotes bajos.
--
-- Va por tabla temporal porque MySQL no deja leer `componente` dentro de un
-- UPDATE sobre `componente`.
DROP TEMPORARY TABLE IF EXISTS tmp_lote_pieza;
CREATE TEMPORARY TABLE tmp_lote_pieza AS
SELECT numero,
       CONCAT('LC-', modelo, '-',
              LPAD(CEIL(ROW_NUMBER() OVER (PARTITION BY modelo ORDER BY numero) / 20),
                   2, '0')) AS lote
  FROM componente
 WHERE modelo IS NOT NULL;

UPDATE componente c
  JOIN tmp_lote_pieza t ON t.numero = c.numero
   SET c.lote = t.lote;

DROP TEMPORARY TABLE tmp_lote_pieza;


-- ============================================================================
--  8. SE RETIRA EL ANDAMIO
-- ============================================================================
DROP PROCEDURE IF EXISTS sp_p2_surtir;
DROP PROCEDURE IF EXISTS sp_p2_montar;
DROP PROCEDURE IF EXISTS sp_p2_inspeccionar;
DROP PROCEDURE IF EXISTS sp_p2_avanzar_hasta;
DROP PROCEDURE IF EXISTS sp_p2_terminar;
DROP PROCEDURE IF EXISTS sp_p2_rechazar;
DROP PROCEDURE IF EXISTS sp_p2_embalar;


-- ============================================================================
--  VERIFICACIÓN
-- ============================================================================

-- Estado de las órdenes. Lo esperado: A y H completadas, F pendiente,
-- E cancelada, el resto en proceso. B tiene que decir 4 de 5, y C y D una
-- rechazada cada una.
SELECT folio, cant_planificada, cant_producida, cant_rechazada, estado, fecha
  FROM orden_produccion ORDER BY folio;

-- Cómo quedaron repartidas las laptops.
SELECT el.nombre AS estado, COUNT(*) AS laptops
  FROM laptop l JOIN edo_laptop el ON el.codigo = l.estado
 GROUP BY el.nombre ORDER BY laptops DESC;

-- Trabajo pendiente por línea: lo que verá cada inspector al entrar.
SELECT re.linea, COUNT(*) AS laptops_paradas
  FROM registro_ensamblaje re
 WHERE re.fecha_fin IS NULL
 GROUP BY re.linea ORDER BY re.linea;

-- Componentes por estado.
SELECT ec.nombre AS estado, COUNT(*) AS piezas
  FROM componente c JOIN edo_componente ec ON ec.codigo = c.estado
 GROUP BY ec.nombre ORDER BY piezas DESC;

-- Piezas que reprobaron alguna inspección.
SELECT di.inspeccion, i.laptop, i.linea, c.num_serie, di.observacion
  FROM detalle_inspeccion di
  JOIN inspeccion_calidad i ON i.numero = di.inspeccion
  JOIN componente c ON c.numero = di.componente
 ORDER BY di.inspeccion;
