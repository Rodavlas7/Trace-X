-- Active: 1783038914702@@localhost@3306@cuatro

-- TRACEX — Datos de prueba (transaccionales)
-- Version: 2026-07-21
--
-- Objetivo : Poblar las tablas transaccionales con datos suficientes para
--            probar TODAS las URLs y funcionalidades de la API.
--
-- REQUISITOS (ejecutar en este orden ANTES que este archivo):
--   1) estructura.sql   -- tablas
--   2) datos.sql        -- catálogos + BOM (modelo_laptop_componente)
--   3) triggers.sql     -- triggers
--
-- Este archivo asume que los catálogos (roles, turnos, estados, tipos,
-- modelos, líneas, estaciones, empleados, lotes y el BOM) YA existen, y
-- solo agrega datos transaccionales encima.
--
-- Los datos se insertan siguiendo el flujo real de producción para no
-- chocar con los triggers (una laptop entra en ENSAMBLAJE, se le registra
-- el ensamblaje y sus componentes, pasa por inspección y luego embalaje).


USE cuatro;


-- ============================================================
--  LIMPIEZA (solo tablas transaccionales; NO toca catálogos ni BOM)
-- ============================================================
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE componente;
TRUNCATE TABLE detalle_inspeccion;
TRUNCATE TABLE detalle_material;
TRUNCATE TABLE inspeccion_calidad;
TRUNCATE TABLE registro_embalaje;
TRUNCATE TABLE registro_ensamblaje;
TRUNCATE TABLE paro;
TRUNCATE TABLE laptop;
TRUNCATE TABLE orden_material;
TRUNCATE TABLE orden_produccion;
SET FOREIGN_KEY_CHECKS = 1;


-- ============================================================
--  1. ÓRDENES DE PRODUCCIÓN
--
--  Cada orden lleva su LOTE: las laptops que se registren contra ella heredan
--  de aquí su modelo y su lote. LOT2026A surte dos órdenes y LOT2026B otras
--  tres, para que se vea la relación 1 lote -> N órdenes.
--
--  Sobre los estados: los folios 1 a 4 se insertan en su estado inicial, pero
--  el trigger tg_Laptop_Alta mueve a 'PROC' cualquier
--  orden 'PEND' en cuanto se le registra una laptop. Por eso el folio 1 termina
--  en 'PROC' y el 5, que se queda sin laptops, es el único que sigue 'PEND'.
--  El folio 3 pasa a 'COMP' por el trigger de embalaje.
--
--  cant_producida y cant_rechazada van en cero en todas: los triggers las
--  llevan sumando y restando, así que un valor sembrado aquí se quedaría
--  sumado de más. Al terminar la carga el folio 2 queda en 1 y 1, y el 3 en 1.
-- ============================================================
INSERT INTO orden_produccion (fecha, hora, modelo_laptop, cant_planificada, cant_producida, cant_rechazada, estado, lote) VALUES
('2026-07-21', '08:00:00', 'ML001', 5, 0, 0, 'PEND', 'LOT2026A'),   -- folio 1 (el trigger la deja en PROC)
('2026-07-21', '09:00:00', 'ML001', 3, 0, 0, 'PROC', 'LOT2026A'),   -- folio 2 (termina con 1 producida y 1 rechazada)
('2026-07-20', '08:00:00', 'ML001', 1, 0, 0, 'PROC', 'LOT2026B'),   -- folio 3 (pasará a COMP por trigger)
('2026-07-19', '08:00:00', 'ML001', 2, 0, 0, 'CANC', 'LOT2026B'),   -- folio 4
('2026-07-22', '07:30:00', 'ML001', 4, 0, 0, 'PEND', 'LOT2026B');   -- folio 5, sin laptops: se queda PEND


-- ============================================================
--  2. LAPTOPS
--
--  El estado que se manda aquí ya no decide nada: tg_Arrancar_Laptop_En_
--  Ensamblaje deja en PENSAM a toda laptop que nazca en REGIS, y acto seguido
--  tg_Laptop_Alta le abre su registro en la línea A. Ese es
--  el arranque del reloj de ensamblaje que pide el proceso.
--
--  Las que terminan APROV/RECHA/EMBALA llegan ahí por el recorrido de la
--  sección 3, no por lo que se escriba en esta columna.
--
--  num_serie es UNIQUE, por eso cada una es distinta.
-- ============================================================
INSERT INTO laptop (num_serie, orden, modelo, estado, lote) VALUES
('TMP-0001',           1, 'ML001', 'REGIS',  'LOT2026A'),  -- numero 1: recién registrada
('TMP-0002',           1, 'ML001', 'PENSAM', 'LOT2026A'),  -- numero 2: en ensamblaje (completa)
('TMP-0003',           1, 'ML001', 'PENSAM', 'LOT2026A'),  -- numero 3: en ensamblaje (parcial)
('TP-20260721-000004', 2, 'ML001', 'PENSAM', 'LOT2026A'),  -- numero 4: será aprobada
('TMP-0005',           2, 'ML001', 'PENSAM', 'LOT2026A'),  -- numero 5: será rechazada
('TMP-0006',           2, 'ML001', 'PENSAM', 'LOT2026A'),  -- numero 6: en ensamblaje
-- Las de las órdenes 3 y 4 llevan LOT2026B, que es el lote de esas órdenes:
-- el lote de una laptop siempre tiene que coincidir con el de su orden.
('TP-20260721-000007', 3, 'ML001', 'PENSAM', 'LOT2026B'),  -- numero 7: será embalada
('TMP-0008',           4, 'ML001', 'REGIS',  'LOT2026B');  -- numero 8: de orden cancelada


-- ============================================================
--  3. RECORRIDO POR LAS LÍNEAS
--
--  Los registros de ensamblaje ya NO se insertan a mano:
--    - el alta de la laptop abre sola el de la primera línea
--      (tg_Laptop_Alta);
--    - cada inspección aprobada cierra el de su línea y abre el de la
--      siguiente (tg_Actualizar_Estado_Laptop_Inspeccion_Calidad).
--
--  Así que aquí se recorre el proceso de verdad: se instalan las piezas que
--  monta la línea donde va la laptop, se inspecciona, y el relevo lo hace la
--  base. @reg guarda el registro ABIERTO de la laptop en turno, y hay que
--  volver a leerlo después de cada inspección aprobada porque el trigger abre
--  uno nuevo.
--
--  A dónde llega cada una:
--    L1  recién registrada, sin piezas         -> abierta en A
--    L2  con las piezas de A                   -> abierta en A
--    L3  pasó A, ya con piezas de B            -> abierta en B
--    L4  pasó A, B, C y D                      -> APROBADA
--    L5  pasó A, rechazada en B por una pieza  -> RECHAZADA
--    L6  pasó A y B                            -> abierta en C
--    L7  pasó todo, se embala más abajo        -> APROBADA -> EMBALADA
--    L8  de orden cancelada, sin piezas        -> abierta en A
--
--  Qué monta cada línea (ver el mapa de estaciones en datos.sql):
--    A  chasis superior, touchpad, teclado, altavoces, conector de carga
--    B  tarjeta madre, procesador, memoria RAM (x2)
--    C  SSD (x2), tarjeta de red, disipador
--    D  pantalla, cámara web, batería, chasis inferior
-- ============================================================

-- El trigger arranca los registros con la fecha de hoy. Se alinean con las del
-- resto del archivo para que los reportes por fecha den algo coherente.
UPDATE registro_ensamblaje
   SET fecha_inicio = '2026-07-21', hora_inicio = '08:00:00'
 WHERE fecha_fin IS NULL;


-- L2 — se queda en la línea A con sus piezas puestas
SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 2 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L2-CHS', 'Chasis superior',   'LIN001', 'MC028', 'LCOMP-001', 'EDC002', @reg),
('CMP-L2-TPD', 'Touchpad',          'LIN001', 'MC020', 'LCOMP-001', 'EDC002', @reg),
('CMP-L2-KBD', 'Teclado',           'LIN001', 'MC018', 'LCOMP-001', 'EDC002', @reg),
('CMP-L2-SPK', 'Altavoces',         'LIN001', 'MC031', 'LCOMP-001', 'EDC002', @reg),
('CMP-L2-PWR', 'Conector de carga', 'LIN001', 'MC030', 'LCOMP-001', 'EDC002', @reg);


-- L3 — pasa la A y se queda a medias en la B
SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 3 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L3-CHS', 'Chasis superior',   'LIN001', 'MC028', 'LCOMP-001', 'EDC002', @reg),
('CMP-L3-TPD', 'Touchpad',          'LIN001', 'MC021', 'LCOMP-001', 'EDC002', @reg),
('CMP-L3-KBD', 'Teclado',           'LIN001', 'MC019', 'LCOMP-001', 'EDC002', @reg),
('CMP-L3-SPK', 'Altavoces',         'LIN001', 'MC031', 'LCOMP-001', 'EDC002', @reg),
('CMP-L3-PWR', 'Conector de carga', 'LIN001', 'MC030', 'LCOMP-001', 'EDC002', @reg);

INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Chasis, teclado y audio correctos', '2026-07-21', '09:10:00', 3, 2607004, 'LIN001');

SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 3 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L3-MB',  'Tarjeta madre', 'LIN002', 'MC012', 'LCOMP-001', 'EDC002', @reg),
('CMP-L3-CPU', 'Procesador',    'LIN002', 'MC001', 'LCOMP-001', 'EDC002', @reg);


-- L4 — recorre las cuatro líneas y sale aprobada
SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 4 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L4-CHS', 'Chasis superior',   'LIN001', 'MC028', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-TPD', 'Touchpad',          'LIN001', 'MC020', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-KBD', 'Teclado',           'LIN001', 'MC018', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-SPK', 'Altavoces',         'LIN001', 'MC031', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-PWR', 'Conector de carga', 'LIN001', 'MC030', 'LCOMP-002', 'EDC002', @reg);
INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Línea A conforme', '2026-07-21', '08:40:00', 4, 2607004, 'LIN001');

SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 4 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L4-MB',   'Tarjeta madre', 'LIN002', 'MC013', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-CPU',  'Procesador',    'LIN002', 'MC002', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-RAM1', 'RAM módulo 1',  'LIN002', 'MC005', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-RAM2', 'RAM módulo 2',  'LIN002', 'MC007', 'LCOMP-002', 'EDC002', @reg);
INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Placa, CPU y RAM conformes', '2026-07-21', '09:20:00', 4, 2607009, 'LIN002');

SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 4 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L4-SSD1', 'SSD 1',         'LIN003', 'MC010', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-SSD2', 'SSD 2',         'LIN003', 'MC009', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-WIFI', 'Tarjeta de red','LIN003', 'MC024', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-THM',  'Disipador',     'LIN003', 'MC027', 'LCOMP-002', 'EDC002', @reg);
INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Almacenamiento, red y térmico conformes', '2026-07-21', '10:05:00', 4, 2607014, 'LIN003');

SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 4 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L4-PAN', 'Pantalla',        'LIN004', 'MC014', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-CAM', 'Cámara web',      'LIN004', 'MC022', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-BAT', 'Batería',         'LIN004', 'MC017', 'LCOMP-002', 'EDC002', @reg),
('CMP-L4-BOT', 'Chasis inferior', 'LIN004', 'MC029', 'LCOMP-002', 'EDC002', @reg);
-- Última línea: esta aprobación sí es la final, la laptop pasa a APROV.
INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Equipo cerrado y probado, aprobada', '2026-07-21', '10:30:00', 4, 2607019, 'LIN004');


-- L5 — pasa la A y la rechazan en la B por un módulo de RAM
SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 5 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L5-CHS', 'Chasis superior',   'LIN001', 'MC028', 'LCOMP-001', 'EDC002', @reg),
('CMP-L5-TPD', 'Touchpad',          'LIN001', 'MC021', 'LCOMP-001', 'EDC002', @reg),
('CMP-L5-KBD', 'Teclado',           'LIN001', 'MC019', 'LCOMP-001', 'EDC002', @reg),
('CMP-L5-SPK', 'Altavoces',         'LIN001', 'MC031', 'LCOMP-001', 'EDC002', @reg),
('CMP-L5-PWR', 'Conector de carga', 'LIN001', 'MC030', 'LCOMP-001', 'EDC002', @reg);
INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Línea A conforme', '2026-07-21', '08:50:00', 5, 2607004, 'LIN001');

SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 5 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L5-MB',   'Tarjeta madre', 'LIN002', 'MC012', 'LCOMP-001', 'EDC002', @reg),
('CMP-L5-CPU',  'Procesador',    'LIN002', 'MC001', 'LCOMP-001', 'EDC002', @reg),
('CMP-L5-RAM1', 'RAM módulo 1',  'LIN002', 'MC005', 'LCOMP-001', 'EDC003', @reg);

INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(0, 'Módulo de RAM no detectado en POST, se rechaza', '2026-07-21', '09:45:00', 5, 2607009, 'LIN002');

-- Aquí se ve para qué sirve detalle_inspeccion: la inspección dice que la laptop
-- se rechaza, y esto dice cuál pieza la reprobó.
SET @insp := LAST_INSERT_ID();
SET @comp := (SELECT numero FROM componente WHERE num_serie = 'CMP-L5-RAM1');
INSERT INTO detalle_inspeccion (inspeccion, componente, observacion) VALUES
(@insp, @comp, 'No lo reconoce el POST; se marca dañado y se devuelve al proveedor');


-- L6 — pasa A y B, se queda abierta en la C
SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 6 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L6-CHS', 'Chasis superior',   'LIN001', 'MC028', 'LCOMP-002', 'EDC002', @reg),
('CMP-L6-TPD', 'Touchpad',          'LIN001', 'MC020', 'LCOMP-002', 'EDC002', @reg),
('CMP-L6-KBD', 'Teclado',           'LIN001', 'MC018', 'LCOMP-002', 'EDC002', @reg),
('CMP-L6-SPK', 'Altavoces',         'LIN001', 'MC031', 'LCOMP-002', 'EDC002', @reg),
('CMP-L6-PWR', 'Conector de carga', 'LIN001', 'MC030', 'LCOMP-002', 'EDC002', @reg);
INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Línea A conforme', '2026-07-21', '09:00:00', 6, 2607004, 'LIN001');

SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 6 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L6-MB',   'Tarjeta madre', 'LIN002', 'MC013', 'LCOMP-002', 'EDC002', @reg),
('CMP-L6-CPU',  'Procesador',    'LIN002', 'MC003', 'LCOMP-002', 'EDC002', @reg),
('CMP-L6-RAM1', 'RAM módulo 1',  'LIN002', 'MC006', 'LCOMP-002', 'EDC002', @reg),
('CMP-L6-RAM2', 'RAM módulo 2',  'LIN002', 'MC007', 'LCOMP-002', 'EDC002', @reg);
INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Placa, CPU y RAM conformes', '2026-07-21', '10:15:00', 6, 2607009, 'LIN002');


-- L7 — recorre todo y queda aprobada; se embala más abajo
SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 7 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L7-CHS', 'Chasis superior',   'LIN001', 'MC028', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-TPD', 'Touchpad',          'LIN001', 'MC021', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-KBD', 'Teclado',           'LIN001', 'MC019', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-SPK', 'Altavoces',         'LIN001', 'MC031', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-PWR', 'Conector de carga', 'LIN001', 'MC030', 'LCOMP-001', 'EDC002', @reg);
INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Línea A conforme', '2026-07-20', '08:30:00', 7, 2607004, 'LIN001');

SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 7 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L7-MB',   'Tarjeta madre', 'LIN002', 'MC012', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-CPU',  'Procesador',    'LIN002', 'MC001', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-RAM1', 'RAM módulo 1',  'LIN002', 'MC005', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-RAM2', 'RAM módulo 2',  'LIN002', 'MC006', 'LCOMP-001', 'EDC002', @reg);
INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Placa, CPU y RAM conformes', '2026-07-20', '09:15:00', 7, 2607009, 'LIN002');

SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 7 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L7-SSD1', 'SSD 1',          'LIN003', 'MC009', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-SSD2', 'SSD 2',          'LIN003', 'MC011', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-WIFI', 'Tarjeta de red', 'LIN003', 'MC025', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-THM',  'Disipador',      'LIN003', 'MC026', 'LCOMP-001', 'EDC002', @reg);
INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Almacenamiento, red y térmico conformes', '2026-07-20', '10:00:00', 7, 2607014, 'LIN003');

SET @reg := (SELECT numero FROM registro_ensamblaje WHERE laptop = 7 AND fecha_fin IS NULL);
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('CMP-L7-PAN', 'Pantalla',        'LIN004', 'MC016', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-CAM', 'Cámara web',      'LIN004', 'MC023', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-BAT', 'Batería',         'LIN004', 'MC017', 'LCOMP-001', 'EDC002', @reg),
('CMP-L7-BOT', 'Chasis inferior', 'LIN004', 'MC029', 'LCOMP-001', 'EDC002', @reg);
INSERT INTO inspeccion_calidad (resultado, observaciones, fecha, hora, laptop, empleado, linea) VALUES
(1, 'Cumple especificaciones, aprobada', '2026-07-20', '11:30:00', 7, 2607019, 'LIN004');


-- Los cierres y los relevos los sella el trigger con la fecha/hora de HOY, que
-- no es la del guion. Se realinean: cada registro cerrado toma la fecha de la
-- inspección que lo cerró, y se le da una duración de 20 minutos. Son 20 y no
-- más porque entre dos inspecciones seguidas de la misma laptop llega a haber
-- solo 25 minutos, y con una duración mayor un registro arrancaría antes de que
-- cerrara el de la línea anterior.
UPDATE registro_ensamblaje re
  JOIN inspeccion_calidad ic
    ON ic.laptop = re.laptop AND ic.linea = re.linea
   SET re.fecha_inicio = ic.fecha,
       re.hora_inicio  = SUBTIME(ic.hora, '00:20:00'),
       re.fecha_fin    = ic.fecha,
       re.hora_fin     = ic.hora
 WHERE re.fecha_fin IS NOT NULL;

-- Y los que el relevo dejó abiertos (L3 en B, L6 en C) arrancan el mismo día.
UPDATE registro_ensamblaje
   SET fecha_inicio = '2026-07-21', hora_inicio = '10:30:00'
 WHERE fecha_fin IS NULL
   AND fecha_inicio = CURDATE();


-- ============================================================
--  4. COMPONENTES SUELTOS EN INVENTARIO  (sin ensamblaje asignado; el
--     trigger de capacidad NO aplica). Sirven para que los endpoints de
--     componentes tengan piezas en estados distintos, no solo Disponible.
--
--     Cada una va en la línea que instala su tipo. Antes estaban regadas
--     (un procesador en LIN001, un teclado en LIN002...) y eso se colaba
--     como stock fantasma en el checklist de registro de ensamblaje: la
--     pantalla lista lo que la línea tiene disponible, así que una pieza
--     en la línea equivocada aparece como si esa línea la instalara.
-- ============================================================
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('INV-CPU-01', 'Procesador en inventario', 'LIN002', 'MC004', 'LCOMP-002', 'EDC001', NULL),
('INV-SSD-01', 'SSD en inventario',        'LIN003', 'MC008', 'LCOMP-001', 'EDC001', NULL),
('INV-PAN-01', 'Pantalla en inventario',   'LIN004', 'MC014', 'LCOMP-001', 'EDC001', NULL),
('INV-KB-01',  'Teclado en inventario',    'LIN001', 'MC018', 'LCOMP-001', 'EDC001', NULL),
('INV-WIFI-01','Wi-Fi en inventario',      'LIN003', 'MC024', 'LCOMP-002', 'EDC001', NULL),
('INV-CAM-01', 'Cámara dañada',            'LIN004', 'MC022', 'LCOMP-001', 'EDC003', NULL),
('INV-BAT-01', 'Batería mermada',          'LIN004', 'MC017', 'LCOMP-002', 'EDC004', NULL);


-- ============================================================
--  5. EMBALAJE  (laptop 7, que quedó APROV, se embala)
--     El trigger la pasa a EMBALA y, como la orden 3 tenía planificada 1
--     y esta es su única laptop embalada, la orden 3 pasa a COMPLETADA.
-- ============================================================
INSERT INTO registro_embalaje (fecha, hora, laptop, tipo) VALUES
('2026-07-20', '12:00:00', 7, 'TE001');


-- ============================================================
--  6. ÓRDENES DE MATERIAL + SUS RENGLONES (detalle_material, PK compuesta)
--
--  Una orden por línea de ensamblaje. Cada una pide EXACTAMENTE los modelos
--  que instalan sus estaciones: es el mismo reparto que el stock, así que una
--  línea nunca se surte de algo que no le toca montar.
--
--  Las cantidades son para unas 40 laptops, repartidas entre los modelos
--  compatibles de cada tipo (los de doble ranura —RAM y SSD— llevan más).
--
--  La línea E no lleva orden: es de embalaje y detalle_material solo apunta a
--  modelo_componente, que son piezas de ensamblaje. Cajas y empaque salen de
--  tipo_embalaje, que es otro catálogo y no cuelga de aquí.
-- ============================================================
INSERT INTO orden_material (solicitud, necesitada, linea) VALUES
('2026-07-21 07:30:00', '2026-07-23 07:00:00', 'LIN001'),   -- numero 1 — Línea A
('2026-07-21 07:45:00', '2026-07-23 07:00:00', 'LIN002'),   -- numero 2 — Línea B
('2026-07-21 08:00:00', '2026-07-23 14:00:00', 'LIN003'),   -- numero 3 — Línea C
('2026-07-21 08:15:00', '2026-07-23 14:00:00', 'LIN004');   -- numero 4 — Línea D

-- Orden 1 · Línea A: chasis superior, touchpad, teclado, altavoces, conector
INSERT INTO detalle_material (orden, modelo, cantidad) VALUES
(1, 'MC028', 40),   -- Lenovo Top Cover T14G5 Negro
(1, 'MC020', 20),   -- Lenovo Touchpad T14G5 NFC
(1, 'MC021', 20),   -- Lenovo Touchpad T14G5 Std
(1, 'MC018', 20),   -- Lenovo KB T14G5 ES Retroilum.
(1, 'MC019', 20),   -- Lenovo KB T14G5 US Retroilum.
(1, 'MC031', 40),   -- Harman 2x2W Speaker T14G5
(1, 'MC030', 40);   -- Lenovo USB-C Power Connector

-- Orden 2 · Línea B: tarjeta madre, procesador, memoria RAM
INSERT INTO detalle_material (orden, modelo, cantidad) VALUES
(2, 'MC012', 20),   -- Lenovo T14 G5 AMD Mainboard
(2, 'MC013', 20),   -- Lenovo T14 G5 Intel Mainboard
(2, 'MC001', 10),   -- AMD Ryzen 5 PRO 7540U
(2, 'MC002', 10),   -- AMD Ryzen 7 PRO 7840U
(2, 'MC003', 10),   -- Intel Core Ultra 5 125U
(2, 'MC004', 10),   -- Intel Core Ultra 7 165U
(2, 'MC005', 30),   -- Samsung 8GB DDR5-5600 SO-DIMM
(2, 'MC006', 30),   -- Samsung 16GB DDR5-5600 SO-DIMM
(2, 'MC007', 30);   -- Micron 32GB DDR5-5600 SO-DIMM

-- Orden 3 · Línea C: SSD, tarjeta de red, disipador
INSERT INTO detalle_material (orden, modelo, cantidad) VALUES
(3, 'MC008', 20),   -- Samsung PM9A1 256GB NVMe M.2
(3, 'MC009', 20),   -- Samsung PM9A1 512GB NVMe M.2
(3, 'MC010', 20),   -- Samsung PM9A1 1TB NVMe M.2
(3, 'MC011', 20),   -- Seagate FireCuda 2TB NVMe M.2
(3, 'MC024', 20),   -- Intel Wi-Fi 6E AX211 M.2
(3, 'MC025', 20),   -- Qualcomm FastConnect 6900 M.2
(3, 'MC026', 20),   -- Lenovo Thermal Module T14G5 AMD
(3, 'MC027', 20);   -- Lenovo Thermal Module T14G5 Int

-- Orden 4 · Línea D: pantalla, cámara web, batería, chasis inferior
INSERT INTO detalle_material (orden, modelo, cantidad) VALUES
(4, 'MC014', 15),   -- BOE 14" FHD IPS 400nit
(4, 'MC015', 15),   -- LG 14" WUXGA IPS Touch 400nit
(4, 'MC016', 15),   -- BOE 14" 2.8K OLED 400nit
(4, 'MC022', 20),   -- Chicony 1080p FHD IR+RGB
(4, 'MC023', 20),   -- Chicony 5MP IR+RGB
(4, 'MC017', 40),   -- Lenovo 52.5Wh Li-Ion T14G5
(4, 'MC029', 40);   -- Lenovo Bottom Cover T14G5


-- ============================================================
--  7. PAROS  (abiertos = fecha_fin NULL ; cerrados = con fecha_fin)
-- ============================================================
INSERT INTO paro (razon, fecha_inicio, fecha_fin, hora_inicio, hora_fin, linea) VALUES
('Falla en banda transportadora',      '2026-07-21', NULL,         '09:00:00', NULL,        'LIN001'),
('Mantenimiento preventivo programado','2026-07-20', '2026-07-20', '14:00:00', '15:30:00',  'LIN002'),
('Falta de suministro de componentes', '2026-07-21', NULL,         '10:15:00', NULL,        'LIN003');



-- ============================================================================
-- STOCK DE COMPONENTES POR LÍNEA  (5 piezas de cada modelo)
--
-- Cada modelo se surte ÚNICAMENTE en la línea cuya estación lo instala:
--   LIN001 -> chasis superior, touchpad, teclado, altavoces, conector de carga
--   LIN002 -> tarjeta madre, procesador, memoria RAM
--   LIN003 -> SSD, tarjeta de red, disipador
--   LIN004 -> pantalla, cámara web, batería, chasis inferior
--   LIN005 -> (embalaje: no surte componentes de ensamblaje)
-- Todas quedan Disponibles (EDC001) y sin ensamblaje asignado.
-- ============================================================================

-- LIN001 · EST-A1 Chasis y Touchpad
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC020-1', 'Lenovo Touchpad T14G5 NFC', 'LIN001', 'MC020', 'LCOMP-001', 'EDC001', NULL),
('STK-MC020-2', 'Lenovo Touchpad T14G5 NFC', 'LIN001', 'MC020', 'LCOMP-001', 'EDC001', NULL),
('STK-MC020-3', 'Lenovo Touchpad T14G5 NFC', 'LIN001', 'MC020', 'LCOMP-001', 'EDC001', NULL),
('STK-MC020-4', 'Lenovo Touchpad T14G5 NFC', 'LIN001', 'MC020', 'LCOMP-002', 'EDC001', NULL),
('STK-MC020-5', 'Lenovo Touchpad T14G5 NFC', 'LIN001', 'MC020', 'LCOMP-002', 'EDC001', NULL),
('STK-MC021-1', 'Lenovo Touchpad T14G5 Std', 'LIN001', 'MC021', 'LCOMP-001', 'EDC001', NULL),
('STK-MC021-2', 'Lenovo Touchpad T14G5 Std', 'LIN001', 'MC021', 'LCOMP-001', 'EDC001', NULL),
('STK-MC021-3', 'Lenovo Touchpad T14G5 Std', 'LIN001', 'MC021', 'LCOMP-001', 'EDC001', NULL),
('STK-MC021-4', 'Lenovo Touchpad T14G5 Std', 'LIN001', 'MC021', 'LCOMP-002', 'EDC001', NULL),
('STK-MC021-5', 'Lenovo Touchpad T14G5 Std', 'LIN001', 'MC021', 'LCOMP-002', 'EDC001', NULL),
('STK-MC028-1', 'Lenovo Top Cover T14G5 Negro', 'LIN001', 'MC028', 'LCOMP-001', 'EDC001', NULL),
('STK-MC028-2', 'Lenovo Top Cover T14G5 Negro', 'LIN001', 'MC028', 'LCOMP-001', 'EDC001', NULL),
('STK-MC028-3', 'Lenovo Top Cover T14G5 Negro', 'LIN001', 'MC028', 'LCOMP-001', 'EDC001', NULL),
('STK-MC028-4', 'Lenovo Top Cover T14G5 Negro', 'LIN001', 'MC028', 'LCOMP-002', 'EDC001', NULL),
('STK-MC028-5', 'Lenovo Top Cover T14G5 Negro', 'LIN001', 'MC028', 'LCOMP-002', 'EDC001', NULL);

-- LIN001 · EST-A2 Módulo de Teclado
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC018-1', 'Lenovo KB T14G5 ES Retroilum.', 'LIN001', 'MC018', 'LCOMP-001', 'EDC001', NULL),
('STK-MC018-2', 'Lenovo KB T14G5 ES Retroilum.', 'LIN001', 'MC018', 'LCOMP-001', 'EDC001', NULL),
('STK-MC018-3', 'Lenovo KB T14G5 ES Retroilum.', 'LIN001', 'MC018', 'LCOMP-001', 'EDC001', NULL),
('STK-MC018-4', 'Lenovo KB T14G5 ES Retroilum.', 'LIN001', 'MC018', 'LCOMP-002', 'EDC001', NULL),
('STK-MC018-5', 'Lenovo KB T14G5 ES Retroilum.', 'LIN001', 'MC018', 'LCOMP-002', 'EDC001', NULL),
('STK-MC019-1', 'Lenovo KB T14G5 US Retroilum.', 'LIN001', 'MC019', 'LCOMP-001', 'EDC001', NULL),
('STK-MC019-2', 'Lenovo KB T14G5 US Retroilum.', 'LIN001', 'MC019', 'LCOMP-001', 'EDC001', NULL),
('STK-MC019-3', 'Lenovo KB T14G5 US Retroilum.', 'LIN001', 'MC019', 'LCOMP-001', 'EDC001', NULL),
('STK-MC019-4', 'Lenovo KB T14G5 US Retroilum.', 'LIN001', 'MC019', 'LCOMP-002', 'EDC001', NULL),
('STK-MC019-5', 'Lenovo KB T14G5 US Retroilum.', 'LIN001', 'MC019', 'LCOMP-002', 'EDC001', NULL);

-- LIN001 · EST-A3 Audio y Conexiones
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC031-1', 'Harman 2x2W Speaker T14G5', 'LIN001', 'MC031', 'LCOMP-001', 'EDC001', NULL),
('STK-MC031-2', 'Harman 2x2W Speaker T14G5', 'LIN001', 'MC031', 'LCOMP-001', 'EDC001', NULL),
('STK-MC031-3', 'Harman 2x2W Speaker T14G5', 'LIN001', 'MC031', 'LCOMP-001', 'EDC001', NULL),
('STK-MC031-4', 'Harman 2x2W Speaker T14G5', 'LIN001', 'MC031', 'LCOMP-002', 'EDC001', NULL),
('STK-MC031-5', 'Harman 2x2W Speaker T14G5', 'LIN001', 'MC031', 'LCOMP-002', 'EDC001', NULL);

-- LIN001 · EST-A4 Conector de Carga
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC030-1', 'Lenovo USB-C Power Connector', 'LIN001', 'MC030', 'LCOMP-001', 'EDC001', NULL),
('STK-MC030-2', 'Lenovo USB-C Power Connector', 'LIN001', 'MC030', 'LCOMP-001', 'EDC001', NULL),
('STK-MC030-3', 'Lenovo USB-C Power Connector', 'LIN001', 'MC030', 'LCOMP-001', 'EDC001', NULL),
('STK-MC030-4', 'Lenovo USB-C Power Connector', 'LIN001', 'MC030', 'LCOMP-002', 'EDC001', NULL),
('STK-MC030-5', 'Lenovo USB-C Power Connector', 'LIN001', 'MC030', 'LCOMP-002', 'EDC001', NULL);

-- LIN002 · EST-B1 Tarjeta Madre
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC012-1', 'Lenovo T14 G5 AMD Mainboard', 'LIN002', 'MC012', 'LCOMP-001', 'EDC001', NULL),
('STK-MC012-2', 'Lenovo T14 G5 AMD Mainboard', 'LIN002', 'MC012', 'LCOMP-001', 'EDC001', NULL),
('STK-MC012-3', 'Lenovo T14 G5 AMD Mainboard', 'LIN002', 'MC012', 'LCOMP-001', 'EDC001', NULL),
('STK-MC012-4', 'Lenovo T14 G5 AMD Mainboard', 'LIN002', 'MC012', 'LCOMP-002', 'EDC001', NULL),
('STK-MC012-5', 'Lenovo T14 G5 AMD Mainboard', 'LIN002', 'MC012', 'LCOMP-002', 'EDC001', NULL),
('STK-MC013-1', 'Lenovo T14 G5 Intel Mainboard', 'LIN002', 'MC013', 'LCOMP-001', 'EDC001', NULL),
('STK-MC013-2', 'Lenovo T14 G5 Intel Mainboard', 'LIN002', 'MC013', 'LCOMP-001', 'EDC001', NULL),
('STK-MC013-3', 'Lenovo T14 G5 Intel Mainboard', 'LIN002', 'MC013', 'LCOMP-001', 'EDC001', NULL),
('STK-MC013-4', 'Lenovo T14 G5 Intel Mainboard', 'LIN002', 'MC013', 'LCOMP-002', 'EDC001', NULL),
('STK-MC013-5', 'Lenovo T14 G5 Intel Mainboard', 'LIN002', 'MC013', 'LCOMP-002', 'EDC001', NULL);

-- LIN002 · EST-B3 CPU y Pasta Térmica
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC001-1', 'AMD Ryzen 5 PRO 7540U', 'LIN002', 'MC001', 'LCOMP-001', 'EDC001', NULL),
('STK-MC001-2', 'AMD Ryzen 5 PRO 7540U', 'LIN002', 'MC001', 'LCOMP-001', 'EDC001', NULL),
('STK-MC001-3', 'AMD Ryzen 5 PRO 7540U', 'LIN002', 'MC001', 'LCOMP-001', 'EDC001', NULL),
('STK-MC001-4', 'AMD Ryzen 5 PRO 7540U', 'LIN002', 'MC001', 'LCOMP-002', 'EDC001', NULL),
('STK-MC001-5', 'AMD Ryzen 5 PRO 7540U', 'LIN002', 'MC001', 'LCOMP-002', 'EDC001', NULL),
('STK-MC002-1', 'AMD Ryzen 7 PRO 7840U', 'LIN002', 'MC002', 'LCOMP-001', 'EDC001', NULL),
('STK-MC002-2', 'AMD Ryzen 7 PRO 7840U', 'LIN002', 'MC002', 'LCOMP-001', 'EDC001', NULL),
('STK-MC002-3', 'AMD Ryzen 7 PRO 7840U', 'LIN002', 'MC002', 'LCOMP-001', 'EDC001', NULL),
('STK-MC002-4', 'AMD Ryzen 7 PRO 7840U', 'LIN002', 'MC002', 'LCOMP-002', 'EDC001', NULL),
('STK-MC002-5', 'AMD Ryzen 7 PRO 7840U', 'LIN002', 'MC002', 'LCOMP-002', 'EDC001', NULL),
('STK-MC003-1', 'Intel Core Ultra 5 125U', 'LIN002', 'MC003', 'LCOMP-001', 'EDC001', NULL),
('STK-MC003-2', 'Intel Core Ultra 5 125U', 'LIN002', 'MC003', 'LCOMP-001', 'EDC001', NULL),
('STK-MC003-3', 'Intel Core Ultra 5 125U', 'LIN002', 'MC003', 'LCOMP-001', 'EDC001', NULL),
('STK-MC003-4', 'Intel Core Ultra 5 125U', 'LIN002', 'MC003', 'LCOMP-002', 'EDC001', NULL),
('STK-MC003-5', 'Intel Core Ultra 5 125U', 'LIN002', 'MC003', 'LCOMP-002', 'EDC001', NULL),
('STK-MC004-1', 'Intel Core Ultra 7 165U', 'LIN002', 'MC004', 'LCOMP-001', 'EDC001', NULL),
('STK-MC004-2', 'Intel Core Ultra 7 165U', 'LIN002', 'MC004', 'LCOMP-001', 'EDC001', NULL),
('STK-MC004-3', 'Intel Core Ultra 7 165U', 'LIN002', 'MC004', 'LCOMP-001', 'EDC001', NULL),
('STK-MC004-4', 'Intel Core Ultra 7 165U', 'LIN002', 'MC004', 'LCOMP-002', 'EDC001', NULL),
('STK-MC004-5', 'Intel Core Ultra 7 165U', 'LIN002', 'MC004', 'LCOMP-002', 'EDC001', NULL);

-- LIN002 · EST-B4 Memoria RAM
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC005-1', 'Samsung 8GB DDR5-5600 SO-DIMM', 'LIN002', 'MC005', 'LCOMP-001', 'EDC001', NULL),
('STK-MC005-2', 'Samsung 8GB DDR5-5600 SO-DIMM', 'LIN002', 'MC005', 'LCOMP-001', 'EDC001', NULL),
('STK-MC005-3', 'Samsung 8GB DDR5-5600 SO-DIMM', 'LIN002', 'MC005', 'LCOMP-001', 'EDC001', NULL),
('STK-MC005-4', 'Samsung 8GB DDR5-5600 SO-DIMM', 'LIN002', 'MC005', 'LCOMP-002', 'EDC001', NULL),
('STK-MC005-5', 'Samsung 8GB DDR5-5600 SO-DIMM', 'LIN002', 'MC005', 'LCOMP-002', 'EDC001', NULL),
('STK-MC006-1', 'Samsung 16GB DDR5-5600 SO-DIMM', 'LIN002', 'MC006', 'LCOMP-001', 'EDC001', NULL),
('STK-MC006-2', 'Samsung 16GB DDR5-5600 SO-DIMM', 'LIN002', 'MC006', 'LCOMP-001', 'EDC001', NULL),
('STK-MC006-3', 'Samsung 16GB DDR5-5600 SO-DIMM', 'LIN002', 'MC006', 'LCOMP-001', 'EDC001', NULL),
('STK-MC006-4', 'Samsung 16GB DDR5-5600 SO-DIMM', 'LIN002', 'MC006', 'LCOMP-002', 'EDC001', NULL),
('STK-MC006-5', 'Samsung 16GB DDR5-5600 SO-DIMM', 'LIN002', 'MC006', 'LCOMP-002', 'EDC001', NULL),
('STK-MC007-1', 'Micron 32GB DDR5-5600 SO-DIMM', 'LIN002', 'MC007', 'LCOMP-001', 'EDC001', NULL),
('STK-MC007-2', 'Micron 32GB DDR5-5600 SO-DIMM', 'LIN002', 'MC007', 'LCOMP-001', 'EDC001', NULL),
('STK-MC007-3', 'Micron 32GB DDR5-5600 SO-DIMM', 'LIN002', 'MC007', 'LCOMP-001', 'EDC001', NULL),
('STK-MC007-4', 'Micron 32GB DDR5-5600 SO-DIMM', 'LIN002', 'MC007', 'LCOMP-002', 'EDC001', NULL),
('STK-MC007-5', 'Micron 32GB DDR5-5600 SO-DIMM', 'LIN002', 'MC007', 'LCOMP-002', 'EDC001', NULL);

-- LIN003 · EST-C1 Almacenamiento SSD
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC008-1', 'Samsung PM9A1 256GB NVMe M.2', 'LIN003', 'MC008', 'LCOMP-001', 'EDC001', NULL),
('STK-MC008-2', 'Samsung PM9A1 256GB NVMe M.2', 'LIN003', 'MC008', 'LCOMP-001', 'EDC001', NULL),
('STK-MC008-3', 'Samsung PM9A1 256GB NVMe M.2', 'LIN003', 'MC008', 'LCOMP-001', 'EDC001', NULL),
('STK-MC008-4', 'Samsung PM9A1 256GB NVMe M.2', 'LIN003', 'MC008', 'LCOMP-002', 'EDC001', NULL),
('STK-MC008-5', 'Samsung PM9A1 256GB NVMe M.2', 'LIN003', 'MC008', 'LCOMP-002', 'EDC001', NULL),
('STK-MC009-1', 'Samsung PM9A1 512GB NVMe M.2', 'LIN003', 'MC009', 'LCOMP-001', 'EDC001', NULL),
('STK-MC009-2', 'Samsung PM9A1 512GB NVMe M.2', 'LIN003', 'MC009', 'LCOMP-001', 'EDC001', NULL),
('STK-MC009-3', 'Samsung PM9A1 512GB NVMe M.2', 'LIN003', 'MC009', 'LCOMP-001', 'EDC001', NULL),
('STK-MC009-4', 'Samsung PM9A1 512GB NVMe M.2', 'LIN003', 'MC009', 'LCOMP-002', 'EDC001', NULL),
('STK-MC009-5', 'Samsung PM9A1 512GB NVMe M.2', 'LIN003', 'MC009', 'LCOMP-002', 'EDC001', NULL),
('STK-MC010-1', 'Samsung PM9A1 1TB NVMe M.2', 'LIN003', 'MC010', 'LCOMP-001', 'EDC001', NULL),
('STK-MC010-2', 'Samsung PM9A1 1TB NVMe M.2', 'LIN003', 'MC010', 'LCOMP-001', 'EDC001', NULL),
('STK-MC010-3', 'Samsung PM9A1 1TB NVMe M.2', 'LIN003', 'MC010', 'LCOMP-001', 'EDC001', NULL),
('STK-MC010-4', 'Samsung PM9A1 1TB NVMe M.2', 'LIN003', 'MC010', 'LCOMP-002', 'EDC001', NULL),
('STK-MC010-5', 'Samsung PM9A1 1TB NVMe M.2', 'LIN003', 'MC010', 'LCOMP-002', 'EDC001', NULL),
('STK-MC011-1', 'Seagate FireCuda 2TB NVMe M.2', 'LIN003', 'MC011', 'LCOMP-001', 'EDC001', NULL),
('STK-MC011-2', 'Seagate FireCuda 2TB NVMe M.2', 'LIN003', 'MC011', 'LCOMP-001', 'EDC001', NULL),
('STK-MC011-3', 'Seagate FireCuda 2TB NVMe M.2', 'LIN003', 'MC011', 'LCOMP-001', 'EDC001', NULL),
('STK-MC011-4', 'Seagate FireCuda 2TB NVMe M.2', 'LIN003', 'MC011', 'LCOMP-002', 'EDC001', NULL),
('STK-MC011-5', 'Seagate FireCuda 2TB NVMe M.2', 'LIN003', 'MC011', 'LCOMP-002', 'EDC001', NULL);

-- LIN003 · EST-C2 Tarjeta de Red
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC024-1', 'Intel Wi-Fi 6E AX211 M.2', 'LIN003', 'MC024', 'LCOMP-001', 'EDC001', NULL),
('STK-MC024-2', 'Intel Wi-Fi 6E AX211 M.2', 'LIN003', 'MC024', 'LCOMP-001', 'EDC001', NULL),
('STK-MC024-3', 'Intel Wi-Fi 6E AX211 M.2', 'LIN003', 'MC024', 'LCOMP-001', 'EDC001', NULL),
('STK-MC024-4', 'Intel Wi-Fi 6E AX211 M.2', 'LIN003', 'MC024', 'LCOMP-002', 'EDC001', NULL),
('STK-MC024-5', 'Intel Wi-Fi 6E AX211 M.2', 'LIN003', 'MC024', 'LCOMP-002', 'EDC001', NULL),
('STK-MC025-1', 'Qualcomm FastConnect 6900 M.2', 'LIN003', 'MC025', 'LCOMP-001', 'EDC001', NULL),
('STK-MC025-2', 'Qualcomm FastConnect 6900 M.2', 'LIN003', 'MC025', 'LCOMP-001', 'EDC001', NULL),
('STK-MC025-3', 'Qualcomm FastConnect 6900 M.2', 'LIN003', 'MC025', 'LCOMP-001', 'EDC001', NULL),
('STK-MC025-4', 'Qualcomm FastConnect 6900 M.2', 'LIN003', 'MC025', 'LCOMP-002', 'EDC001', NULL),
('STK-MC025-5', 'Qualcomm FastConnect 6900 M.2', 'LIN003', 'MC025', 'LCOMP-002', 'EDC001', NULL);

-- LIN003 · EST-C3 Disipador Térmico
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC026-1', 'Lenovo Thermal Module T14G5 AMD', 'LIN003', 'MC026', 'LCOMP-001', 'EDC001', NULL),
('STK-MC026-2', 'Lenovo Thermal Module T14G5 AMD', 'LIN003', 'MC026', 'LCOMP-001', 'EDC001', NULL),
('STK-MC026-3', 'Lenovo Thermal Module T14G5 AMD', 'LIN003', 'MC026', 'LCOMP-001', 'EDC001', NULL),
('STK-MC026-4', 'Lenovo Thermal Module T14G5 AMD', 'LIN003', 'MC026', 'LCOMP-002', 'EDC001', NULL),
('STK-MC026-5', 'Lenovo Thermal Module T14G5 AMD', 'LIN003', 'MC026', 'LCOMP-002', 'EDC001', NULL),
('STK-MC027-1', 'Lenovo Thermal Module T14G5 Int', 'LIN003', 'MC027', 'LCOMP-001', 'EDC001', NULL),
('STK-MC027-2', 'Lenovo Thermal Module T14G5 Int', 'LIN003', 'MC027', 'LCOMP-001', 'EDC001', NULL),
('STK-MC027-3', 'Lenovo Thermal Module T14G5 Int', 'LIN003', 'MC027', 'LCOMP-001', 'EDC001', NULL),
('STK-MC027-4', 'Lenovo Thermal Module T14G5 Int', 'LIN003', 'MC027', 'LCOMP-002', 'EDC001', NULL),
('STK-MC027-5', 'Lenovo Thermal Module T14G5 Int', 'LIN003', 'MC027', 'LCOMP-002', 'EDC001', NULL);

-- LIN004 · EST-D1 Módulo de Pantalla
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC014-1', 'BOE 14" FHD IPS 400nit', 'LIN004', 'MC014', 'LCOMP-001', 'EDC001', NULL),
('STK-MC014-2', 'BOE 14" FHD IPS 400nit', 'LIN004', 'MC014', 'LCOMP-001', 'EDC001', NULL),
('STK-MC014-3', 'BOE 14" FHD IPS 400nit', 'LIN004', 'MC014', 'LCOMP-001', 'EDC001', NULL),
('STK-MC014-4', 'BOE 14" FHD IPS 400nit', 'LIN004', 'MC014', 'LCOMP-002', 'EDC001', NULL),
('STK-MC014-5', 'BOE 14" FHD IPS 400nit', 'LIN004', 'MC014', 'LCOMP-002', 'EDC001', NULL),
('STK-MC015-1', 'LG 14" WUXGA IPS Touch 400nit', 'LIN004', 'MC015', 'LCOMP-001', 'EDC001', NULL),
('STK-MC015-2', 'LG 14" WUXGA IPS Touch 400nit', 'LIN004', 'MC015', 'LCOMP-001', 'EDC001', NULL),
('STK-MC015-3', 'LG 14" WUXGA IPS Touch 400nit', 'LIN004', 'MC015', 'LCOMP-001', 'EDC001', NULL),
('STK-MC015-4', 'LG 14" WUXGA IPS Touch 400nit', 'LIN004', 'MC015', 'LCOMP-002', 'EDC001', NULL),
('STK-MC015-5', 'LG 14" WUXGA IPS Touch 400nit', 'LIN004', 'MC015', 'LCOMP-002', 'EDC001', NULL),
('STK-MC016-1', 'BOE 14" 2.8K OLED 400nit', 'LIN004', 'MC016', 'LCOMP-001', 'EDC001', NULL),
('STK-MC016-2', 'BOE 14" 2.8K OLED 400nit', 'LIN004', 'MC016', 'LCOMP-001', 'EDC001', NULL),
('STK-MC016-3', 'BOE 14" 2.8K OLED 400nit', 'LIN004', 'MC016', 'LCOMP-001', 'EDC001', NULL),
('STK-MC016-4', 'BOE 14" 2.8K OLED 400nit', 'LIN004', 'MC016', 'LCOMP-002', 'EDC001', NULL),
('STK-MC016-5', 'BOE 14" 2.8K OLED 400nit', 'LIN004', 'MC016', 'LCOMP-002', 'EDC001', NULL),
('STK-MC022-1', 'Chicony 1080p FHD IR+RGB', 'LIN004', 'MC022', 'LCOMP-001', 'EDC001', NULL),
('STK-MC022-2', 'Chicony 1080p FHD IR+RGB', 'LIN004', 'MC022', 'LCOMP-001', 'EDC001', NULL),
('STK-MC022-3', 'Chicony 1080p FHD IR+RGB', 'LIN004', 'MC022', 'LCOMP-001', 'EDC001', NULL),
('STK-MC022-4', 'Chicony 1080p FHD IR+RGB', 'LIN004', 'MC022', 'LCOMP-002', 'EDC001', NULL),
('STK-MC022-5', 'Chicony 1080p FHD IR+RGB', 'LIN004', 'MC022', 'LCOMP-002', 'EDC001', NULL),
('STK-MC023-1', 'Chicony 5MP IR+RGB', 'LIN004', 'MC023', 'LCOMP-001', 'EDC001', NULL),
('STK-MC023-2', 'Chicony 5MP IR+RGB', 'LIN004', 'MC023', 'LCOMP-001', 'EDC001', NULL),
('STK-MC023-3', 'Chicony 5MP IR+RGB', 'LIN004', 'MC023', 'LCOMP-001', 'EDC001', NULL),
('STK-MC023-4', 'Chicony 5MP IR+RGB', 'LIN004', 'MC023', 'LCOMP-002', 'EDC001', NULL),
('STK-MC023-5', 'Chicony 5MP IR+RGB', 'LIN004', 'MC023', 'LCOMP-002', 'EDC001', NULL);

-- LIN004 · EST-D4 Batería Principal
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC017-1', 'Lenovo 52.5Wh Li-Ion T14G5', 'LIN004', 'MC017', 'LCOMP-001', 'EDC001', NULL),
('STK-MC017-2', 'Lenovo 52.5Wh Li-Ion T14G5', 'LIN004', 'MC017', 'LCOMP-001', 'EDC001', NULL),
('STK-MC017-3', 'Lenovo 52.5Wh Li-Ion T14G5', 'LIN004', 'MC017', 'LCOMP-001', 'EDC001', NULL),
('STK-MC017-4', 'Lenovo 52.5Wh Li-Ion T14G5', 'LIN004', 'MC017', 'LCOMP-002', 'EDC001', NULL),
('STK-MC017-5', 'Lenovo 52.5Wh Li-Ion T14G5', 'LIN004', 'MC017', 'LCOMP-002', 'EDC001', NULL);

-- LIN004 · EST-D5 Chasis Inferior
INSERT INTO componente (num_serie, descripcion, linea, modelo, lote, estado, registro_ensamblaje) VALUES
('STK-MC029-1', 'Lenovo Bottom Cover T14G5', 'LIN004', 'MC029', 'LCOMP-001', 'EDC001', NULL),
('STK-MC029-2', 'Lenovo Bottom Cover T14G5', 'LIN004', 'MC029', 'LCOMP-001', 'EDC001', NULL),
('STK-MC029-3', 'Lenovo Bottom Cover T14G5', 'LIN004', 'MC029', 'LCOMP-001', 'EDC001', NULL),
('STK-MC029-4', 'Lenovo Bottom Cover T14G5', 'LIN004', 'MC029', 'LCOMP-002', 'EDC001', NULL),
('STK-MC029-5', 'Lenovo Bottom Cover T14G5', 'LIN004', 'MC029', 'LCOMP-002', 'EDC001', NULL);


-- ============================================================
--  VERIFICACIÓN — resumen de lo insertado
-- ============================================================
SELECT 'orden_produccion' AS tabla, COUNT(*) AS filas FROM orden_produccion
UNION ALL SELECT 'laptop',              COUNT(*) FROM laptop
UNION ALL SELECT 'registro_ensamblaje', COUNT(*) FROM registro_ensamblaje
UNION ALL SELECT 'componente',          COUNT(*) FROM componente
UNION ALL SELECT 'inspeccion_calidad',  COUNT(*) FROM inspeccion_calidad
UNION ALL SELECT 'registro_embalaje',   COUNT(*) FROM registro_embalaje
UNION ALL SELECT 'orden_material',      COUNT(*) FROM orden_material
UNION ALL SELECT 'detalle_material',    COUNT(*) FROM detalle_material
UNION ALL SELECT 'paro',                COUNT(*) FROM paro;

-- Estados finales de laptops (deberían verse REGIS, PENSAM, APROV, RECHA, EMBALA)
SELECT numero, num_serie, estado FROM laptop ORDER BY numero;

-- Estados finales de órdenes. Esperado:
--   1 PROC (el trigger la arrancó al registrarle laptops)
--   2 PROC
--   3 COMP (trigger de embalaje)
--   4 CANC
--   5 PEND (sin laptops, es la única que sigue Pendiente)
SELECT folio, estado, lote, cant_planificada FROM orden_produccion ORDER BY folio;
