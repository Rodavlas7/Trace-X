-- Active: 1783038914702@@localhost@3306@cuatro

-- TRACEX — Catálogo inicial de datos
-- Laptop: Lenovo ThinkPad T14 Gen 5
-- Version: 2026-07-20


USE cuatro;


-- Desactivar validación de FKs para poder borrar en cualquier orden
SET FOREIGN_KEY_CHECKS = 0;
 
TRUNCATE TABLE componente;
TRUNCATE TABLE modelo_laptop_componente;
TRUNCATE TABLE detalle_material;
TRUNCATE TABLE inspeccion_calidad;
TRUNCATE TABLE registro_embalaje;
TRUNCATE TABLE registro_ensamblaje;
TRUNCATE TABLE paro;
TRUNCATE TABLE laptop;
TRUNCATE TABLE lote_laptop;
TRUNCATE TABLE lote_comp;
TRUNCATE TABLE orden_material;
TRUNCATE TABLE orden_produccion;
TRUNCATE TABLE empleado_estacion;
TRUNCATE TABLE empleado_linea;
TRUNCATE TABLE estacion;
TRUNCATE TABLE linea;
TRUNCATE TABLE sesion;
TRUNCATE TABLE usuario;
TRUNCATE TABLE empleado;
TRUNCATE TABLE modelo_componente;
TRUNCATE TABLE modelo_laptop;
TRUNCATE TABLE tipo_comp;
TRUNCATE TABLE tipo_embalaje;
TRUNCATE TABLE tipo_linea;
TRUNCATE TABLE edo_componente;
TRUNCATE TABLE edo_laptop;
TRUNCATE TABLE edo_linea;
TRUNCATE TABLE edo_produccion;
TRUNCATE TABLE rol;
TRUNCATE TABLE turno;
TRUNCATE TABLE estacion_compatibilidad_componente;
 
-- Reactivar validación de FKs

-- 1. ROLES

INSERT INTO rol (codigo, nombre, descripcion) VALUES
('ADMIN', 'Administrador',       'Acceso total al sistema, gestión de usuarios y configuración general'),
('SUPER', 'Supervisor',          'Supervisión de líneas de ensamblaje, asignación de personal y consulta de reportes'),
('OPENSA', 'Operario Ensamblaje', 'Registro de ensamblaje y asociación de componentes en estaciones de trabajo'),
('OPCALI', 'Inspector Calidad',   'Registro y consulta de inspecciones de calidad de laptops'),
('OPEMBA', 'Operario Embalaje',   'Registro del proceso de embalaje y actualización de estado final');


-- 2. TURNOS

INSERT INTO turno (codigo, nombre, hora_entrada, hora_salida) VALUES
('MAT', 'Matutino',   '06:00:00', '14:00:00'),
('VES', 'Vespertino', '14:00:00', '22:00:00');

-- 3. ESTADOS DE LÍNEA

INSERT INTO edo_linea (codigo, nombre, descripcion) VALUES
('ACTI', 'Activa',       'Línea en operación normal'),
('INAC', 'Inactiva',     'Línea fuera de operación temporalmente'),
('PARO', 'En Paro',      'Línea detenida por incidencia registrada'),
('MANT', 'Mantenimiento','Línea en proceso de mantenimiento preventivo o correctivo');


-- 3.1 TIPOS DE LÍNEA
--
-- El tipo dice QUÉ PROCESO corre la línea, no cómo está (eso es edo_linea).
-- Solo en una línea de tipo ENSA se puede registrar ensamblaje: lo obliga el
-- trigger tg_Validar_Apertura_Ensamblaje (DB/triggers.sql).

INSERT INTO tipo_linea (codigo, nombre, descripcion) VALUES
('ENSA', 'Ensamblaje', 'Línea donde se arman las laptops a partir de componentes'),
('EMBA', 'Embalaje',   'Línea donde se empacan y sellan las laptops terminadas');


-- 4. ESTADOS DE LAPTOP 

INSERT INTO edo_laptop (codigo, nombre) VALUES
('REGIS', 'Registrada'),       
('PENSAM', 'En Ensamblaje'),  
('APROV', 'Aprobada'),         
('RECHA', 'Rechazada'),
('EMBALA', 'Embalada');         


-- 5. ESTADOS DE COMPONENTE

INSERT INTO edo_componente (codigo, nombre, descripcion) VALUES
('EDC001', 'Disponible', 'Componente en inventario listo para ensamblaje'),
('EDC002', 'En Uso',     'Componente asignado e instalado en una laptop'),
('EDC003', 'Dañado',     'Componente con defecto de fábrica o dañado en proceso'),
('EDC004', 'Mermado',    'Componente descartado o perdido');


-- 6. ESTADOS DE PRODUCCIÓN 

INSERT INTO edo_produccion (codigo, nombre) VALUES
('PEND', 'Pendiente'),
('PROC', 'En Proceso'),
('COMP', 'Completada'),
('CANC', 'Cancelada');


-- 7. TIPOS DE COMPONENTE

-- 'necesario' es el tipo que tiene que estar montado ANTES que éste. Encadenados
-- forman el orden de armado, y es lo que la pantalla de registro de ensamblaje usa
-- para ir habilitando las casillas del checklist.
--
-- El orden es el de las estaciones (ver más abajo, sección 12), que a su vez es el
-- de la línea de producción real: se arranca del CHASIS SUPERIOR —el top cover es
-- la pieza estructural sobre la que se arma todo— y se cierra con el CHASIS
-- INFERIOR, que es la tapa que se atornilla al final. Por eso cada tipo apunta al
-- de la estación anterior: así ninguna línea puede adelantarse a la que va antes,
-- y el stock de cada línea alcanza justo para sus estaciones.
--
--   Línea A (LIN001)  A1 Chasis Superior · A1 Touchpad · A2 Teclado
--                     A3 Altavoces · A4 Conector de Carga
--   Línea B (LIN002)  B1 Tarjeta Madre · B3 Procesador · B4 Memoria RAM
--   Línea C (LIN003)  C1 SSD · C2 Tarjeta de Red · C3 Disipador
--   Línea D (LIN004)  D1 Pantalla · D1 Cámara Web · D4 Batería
--                     D5 Chasis Inferior
--   Línea E (LIN005)  Embalaje: no monta componentes
INSERT INTO tipo_comp (codigo, nombre, necesario) VALUES
('TC012', 'Chasis Superior', NULL),        -- A1  por aquí se empieza
('TC008', 'Touchpad', 'TC012'),            -- A1
('TC007', 'Teclado', 'TC008'),             -- A2
('TC015', 'Altavoces', 'TC007'),           -- A3
('TC014', 'Conector de Carga', 'TC015'),   -- A4
('TC004', 'Tarjeta Madre', 'TC014'),       -- B1  cierra la línea A, abre la B
('TC001', 'Procesador', 'TC004'),          -- B3
('TC002', 'Memoria RAM', 'TC001'),         -- B4
('TC003', 'Almacenamiento SSD', 'TC002'),  -- C1
('TC010', 'Tarjeta de Red', 'TC003'),      -- C2
('TC011', 'Disipador / Ventilador', 'TC010'), -- C3
('TC005', 'Pantalla', 'TC011'),            -- D1
('TC009', 'Cámara Web', 'TC005'),          -- D1
('TC006', 'Batería', 'TC009'),             -- D4
('TC013', 'Chasis Inferior', 'TC006');     -- E1  la tapa, hasta el final


-- 8. TIPOS DE EMBALAJE

INSERT INTO tipo_embalaje (codigo, nombre) VALUES
('TE001', 'Caja Estándar'),
('TE002', 'Caja Reforzada'),
('TE003', 'Empaque Acolchado'),
('TE004', 'Caja con Espuma de Protección');


-- 9. MODELOS DE LAPTOP

INSERT INTO modelo_laptop (codigo, nombre) VALUES
('ML001', 'ThinkPad T14 Gen 5');


-- 10. MODELOS DE COMPONENTE (ThinkPad T14 Gen 5)

INSERT INTO modelo_componente (codigo, nombre, tipo_componente, fabricante) VALUES
-- Procesadores
('MC001', 'AMD Ryzen 5 PRO 7540U',           'TC001', 'AMD'     ),
('MC002', 'AMD Ryzen 7 PRO 7840U',           'TC001', 'AMD'     ),
('MC003', 'Intel Core Ultra 5 125U',         'TC001', 'Intel'   ),
('MC004', 'Intel Core Ultra 7 165U',         'TC001', 'Intel'   ),
-- Memorias RAM
('MC005', 'Samsung 8GB DDR5-5600 SO-DIMM',  'TC002', 'Samsung' ),
('MC006', 'Samsung 16GB DDR5-5600 SO-DIMM', 'TC002', 'Samsung' ),
('MC007', 'Micron 32GB DDR5-5600 SO-DIMM',  'TC002', 'Micron'  ),
-- Almacenamiento SSD
('MC008', 'Samsung PM9A1 256GB NVMe M.2',   'TC003', 'Samsung' ),
('MC009', 'Samsung PM9A1 512GB NVMe M.2',   'TC003', 'Samsung' ),
('MC010', 'Samsung PM9A1 1TB NVMe M.2',     'TC003', 'Samsung' ),
('MC011', 'Seagate FireCuda 2TB NVMe M.2',  'TC003', 'Seagate' ),
-- Tarjeta Madre
('MC012', 'Lenovo T14 G5 AMD Mainboard',    'TC004', 'Lenovo'  ),
('MC013', 'Lenovo T14 G5 Intel Mainboard',  'TC004', 'Lenovo'  ),
-- Pantalla
('MC014', 'BOE 14" FHD IPS 400nit',         'TC005', 'BOE'     ),
('MC015', 'LG 14" WUXGA IPS Touch 400nit',  'TC005', 'LG'      ),
('MC016', 'BOE 14" 2.8K OLED 400nit',       'TC005', 'BOE'     ),
-- Batería
('MC017', 'Lenovo 52.5Wh Li-Ion T14G5',     'TC006', 'Lenovo'  ),
-- Teclado
('MC018', 'Lenovo KB T14G5 ES Retroilum.',  'TC007', 'Lenovo'  ),
('MC019', 'Lenovo KB T14G5 US Retroilum.',  'TC007', 'Lenovo'  ),
-- Touchpad
('MC020', 'Lenovo Touchpad T14G5 NFC',      'TC008', 'Lenovo'  ),
('MC021', 'Lenovo Touchpad T14G5 Std',      'TC008', 'Lenovo'  ),
-- Cámara Web
('MC022', 'Chicony 1080p FHD IR+RGB',       'TC009', 'Chicony' ),
('MC023', 'Chicony 5MP IR+RGB',             'TC009', 'Chicony' ),
-- Tarjeta de Red
('MC024', 'Intel Wi-Fi 6E AX211 M.2',       'TC010', 'Intel'   ),
('MC025', 'Qualcomm FastConnect 6900 M.2',  'TC010', 'Qualcomm'),
-- Disipador
('MC026', 'Lenovo Thermal Module T14G5 AMD','TC011', 'Lenovo'  ),
('MC027', 'Lenovo Thermal Module T14G5 Int','TC011', 'Lenovo'  ),
-- Chasis
('MC028', 'Lenovo Top Cover T14G5 Negro',   'TC012', 'Lenovo'  ),
('MC029', 'Lenovo Bottom Cover T14G5',      'TC013', 'Lenovo'  ),
-- Conector de carga
('MC030', 'Lenovo USB-C Power Connector',   'TC014', 'Lenovo'  ),
-- Altavoces
('MC031', 'Harman 2x2W Speaker T14G5',      'TC015', 'Harman'  );


-- 10.1 COMPATIBILIDAD — BOM (Bill of Materials / Lista de Materiales)
-- modelos de componente registrados como compatibles con él.
-- La capacidad indica cuántos puede llevar

INSERT INTO modelo_laptop_componente (modelo_laptop, modelo_componente, capacidad)
SELECT 'ML001', mc.codigo,
       CASE mc.tipo_componente
           WHEN 'TC002' THEN 2   -- Memoria RAM: hasta 2 módulos
           WHEN 'TC003' THEN 2   -- Almacenamiento SSD: hasta 2 unidades
           ELSE 1
       END
FROM modelo_componente mc;


-- 11. LÍNEAS DE PRODUCCIÓN
-- 4 de ensamblaje (tipo ENSA) y una de embalaje (tipo EMBA). El tipo ya no se
-- adivina del nombre: es la columna `tipo`, y es la que decide dónde se puede
-- registrar ensamblaje.
--
-- `siguiente` encadena el flujo: A -> B -> C -> D -> E(embalaje). El chasis
-- inferior lo cierra la D, en su estación D5.

INSERT INTO linea (codigo, nombre, descripcion, tipo, estado, siguiente) VALUES
('LIN001', 'Línea A — Ensamblaje', 'Ensamblaje ThinkPad T14 Gen 5',         'ENSA', 'ACTI','LIN002'),
('LIN002', 'Línea B — Ensamblaje', 'Ensamblaje ThinkPad T14 Gen 5',         'ENSA', 'ACTI','LIN003'),
('LIN003', 'Línea C — Ensamblaje', 'Ensamblaje ThinkPad T14 Gen 5',         'ENSA', 'ACTI','LIN004'),
('LIN004', 'Línea D — Ensamblaje', 'Ensamblaje ThinkPad T14 Gen 5',         'ENSA', 'ACTI','LIN005'),
('LIN005', 'Línea E — Embalaje',   'Proceso de embalaje y empaque final',   'EMBA', 'ACTI', NULL);


-- 12. ESTACIONES — Líneas de ensamblaje
--
--  EST-X1  Preparación y verificación de componentes
--  EST-X2  Ensamblaje de placa y procesador
--  EST-X3  Integración de pantalla, teclado y chasis
--  EST-X4  Pruebas funcionales y cierre
--
-- Cada línea de ensamblaje cierra con una estación de calidad, que es donde se
-- para el empleado con rol OPCALI de esa línea.
INSERT INTO estacion (codigo, nombre, descripcion, linea, activo) VALUES
('EST-A1', 'A1 — Chasis y Touchpad',    'Inspección del chasis superior e instalación y atornillado del touchpad en ensamblaje',                 'LIN001', TRUE),
('EST-A2', 'A2 — Módulo de Teclado',    'Colocación del teclado retroiluminado, fijación y ruteo inicial del flexor en ensamblaje',              'LIN001', TRUE),
('EST-A3', 'A3 — Audio y Conexiones',   'Montaje de altavoces, enrutamiento de cables de audio y fijación acústica en ensamblaje',               'LIN001', TRUE),
('EST-A4', 'A4 — Conector de Carga',    'Instalación del conector de carga USB-C, anclaje al chasis y revisión de puertos en ensamblaje',        'LIN001', TRUE),
('EST-A5', 'A5 — Inspección de Calidad','Revisión del inspector sobre chasis, teclado, audio y conector, y registro del resultado de inspección','LIN001', TRUE);

-- Línea B: Tarjeta Madre y Procesamiento
INSERT INTO estacion (codigo, nombre, descripcion, linea, activo) VALUES
('EST-B1', 'B1 — Tarjeta Madre',        'Colocación de la tarjeta madre en el chasis superior y fijación con tornillos en ensamblaje',           'LIN002', TRUE),
('EST-B2', 'B2 — Conexión de Periféricos','Conexión de los flexores del teclado, touchpad y altavoces a la tarjeta madre en ensamblaje',         'LIN002', TRUE),
('EST-B3', 'B3 — CPU y Pasta Térmica',  'Montaje del procesador en el socket y aplicación de pasta térmica en ensamblaje',                       'LIN002', TRUE),
('EST-B4', 'B4 — Memoria RAM',          'Inserción de módulos de memoria RAM en las ranuras SO-DIMM y aseguramiento en ensamblaje',              'LIN002', TRUE),
('EST-B5', 'B5 — Inspección de Calidad','Revisión del inspector sobre tarjeta madre, CPU, RAM y flexores, y registro del resultado de inspección','LIN002', TRUE);

-- Línea C: Almacenamiento, Red y Refrigeración
INSERT INTO estacion (codigo, nombre, descripcion, linea, activo) VALUES
('EST-C1', 'C1 — Almacenamiento SSD',   'Instalación de la unidad NVMe M.2 y fijación del tornillo de retención en ensamblaje',                  'LIN003', TRUE),
('EST-C2', 'C2 — Tarjeta de Red',       'Instalación del módulo Wi-Fi y conexión cuidadosa de las antenas de red en ensamblaje',                 'LIN003', TRUE),
('EST-C3', 'C3 — Disipador Térmico',    'Montaje del módulo térmico sobre el procesador y atornillado en cruz en ensamblaje',                    'LIN003', TRUE),
('EST-C4', 'C4 — Conexión de Ventilación','Conexión del cable de alimentación del ventilador a la tarjeta madre en ensamblaje',                  'LIN003', TRUE),
('EST-C5', 'C5 — Inspección de Calidad','Revisión del inspector sobre SSD, tarjeta de red y módulo térmico, y registro del resultado de inspección','LIN003', TRUE);

-- Línea D: Ensamblaje de Pantalla y Energía
INSERT INTO estacion (codigo, nombre, descripcion, linea, activo) VALUES
('EST-D1', 'D1 — Módulo de Pantalla',   'Preparación de la pantalla e instalación de la cámara web en el marco en ensamblaje',                   'LIN004', TRUE),
('EST-D2', 'D2 — Bisagras y Enrutamiento','Acoplamiento de las bisagras de pantalla al chasis principal y enrutamiento de cables en ensamblaje', 'LIN004', TRUE),
('EST-D3', 'D3 — Conexión de Video',    'Conexión del cable de video (eDP) y cable de cámara a la tarjeta madre en ensamblaje',                  'LIN004', TRUE),
('EST-D4', 'D4 — Batería Principal',    'Colocación de la batería de Li-Ion, atornillado y conexión de alimentación a la placa en ensamblaje',   'LIN004', TRUE),
-- La D cierra el equipo: el chasis inferior, que antes montaba la desaparecida
-- línea E, entra aquí. Va después de la batería —la tapa sella lo que ya quedó
-- adentro— y antes de calidad, que siempre es la última estación de la línea.
('EST-D5', 'D5 — Chasis Inferior',      'Colocación de la tapa inferior (Bottom Cover) y atornillado final del equipo en ensamblaje',            'LIN004', TRUE),
('EST-D6', 'D6 — Inspección de Calidad','Revisión del inspector sobre pantalla, bisagras, video, batería y cierre, y registro del resultado de inspección','LIN004', TRUE);

-- Línea E: Embalaje
INSERT INTO estacion (codigo, nombre, descripcion, linea, activo) VALUES
('EST-E1', 'E1 — Limpieza y Escaneo',   'Revisión estética final, limpieza de pantalla, chasis y escaneo del número de serie en embalaje',     'LIN005', TRUE),
('EST-E2', 'E2 — Empaque y Sellado',    'Colocación en caja con material de protección, inclusión de manuales y sellado final en embalaje',    'LIN005', TRUE),
('EST-E3', 'E3 — Inspección de Calidad','Verificación del empaquetado, sellado y etiquetado por el inspector, y registro del resultado de inspección','LIN005', TRUE);


-- 12.1 COMPATIBILIDAD DE ESTACIONES CON COMPONENTES QUE ENSAMBLAN
INSERT INTO estacion_compatibilidad_componente (estacion, modelo_componente) VALUES

('EST-A1', 'MC028'),  -- Chasis Superior
('EST-A1', 'MC020'),  -- Touchpad
('EST-A1', 'MC021'),  -- Touchpad
('EST-A2', 'MC018'),  -- Teclado
('EST-A2', 'MC019'),  -- Teclado
('EST-A3', 'MC031'),  -- Altavoces
('EST-A4', 'MC030'),  -- Conector de Carga

('EST-B1', 'MC012'),  -- Tarjeta Madre
('EST-B1', 'MC013'),  -- Tarjeta Madre
('EST-B3', 'MC001'),  -- Procesador
('EST-B3', 'MC002'),  -- Procesador
('EST-B3', 'MC003'),  -- Procesador
('EST-B3', 'MC004'),  -- Procesador
('EST-B4', 'MC005'),  -- Memoria RAM
('EST-B4', 'MC006'),  -- Memoria RAM
('EST-B4', 'MC007'),  -- Memoria RAM

('EST-C1', 'MC008'),  -- Almacenamiento SSD
('EST-C1', 'MC009'),  -- Almacenamiento SSD
('EST-C1', 'MC010'),  -- Almacenamiento SSD
('EST-C1', 'MC011'),  -- Almacenamiento SSD
('EST-C2', 'MC024'),  -- Tarjeta de Red
('EST-C2', 'MC025'),  -- Tarjeta de Red
('EST-C3', 'MC026'),  -- Disipador / Ventilador
('EST-C3', 'MC027'),  -- Disipador / Ventilador

('EST-D1', 'MC014'),  -- Pantalla
('EST-D1', 'MC015'),  -- Pantalla
('EST-D1', 'MC016'),  -- Pantalla
('EST-D2', 'MC014'),  -- Pantalla
('EST-D2', 'MC015'),  -- Pantalla
('EST-D2', 'MC016'),  -- Pantalla
('EST-D3', 'MC022'),  -- Cámara Web
('EST-D3', 'MC023'),  -- Cámara Web
('EST-D4', 'MC017'),  -- Batería
('EST-D5', 'MC029');  -- Chasis Inferior


-- 13. LOTE DE LAPTOPS

INSERT INTO lote_laptop (codigo, fecha) VALUES
('LOT2026A', '2026-07-15'),
('LOT2026B', '2026-07-20'),
('LOT2026C', '2026-08-07');


-- 14. LOTE DE COMPONENTES
--
-- Aquí no se siembra ninguno. Un lote de componente es lo que llegó junto del
-- proveedor, así que no tiene sentido sin las piezas que lo forman: los arma
-- la sección 7 de datos_pruebas2.sql, uno por cada 20 piezas del mismo modelo,
-- una vez que todas existen.
--
-- Antes había dos de ejemplo, 'LCOMP-001' (AMD) y 'LCOMP-002' (Intel), que se
-- repartían las 1465 piezas casi en mitades. Como un mismo lote acababa
-- teniendo chasis, teclados y bisagras, no describía ninguna llegada real y
-- vista_traza_orden_componentes veía los mismos dos lotes en todas las órdenes.



-- 15. EMPLEADOS


-- LINEA A para el equipo matutino
INSERT INTO empleado (numero, nombrePila, primerApell, segundoApell, rol, turno, activo) VALUES
(2607001, 'Ana Maria',       'Antonio',     'Cova',     'OPENSA', 'MAT', TRUE),
(2607002, 'Samanta Denisse', 'Contreras',   'Rangel',   'OPENSA', 'MAT', TRUE),
(2607003, 'Luis Alberto',    'Cruz',        'Ortiz',    'OPENSA', 'MAT', TRUE),
(2607004, 'Ricardo Daniel',  'De La Torre', 'Garcia',   'OPCALI', 'MAT', TRUE),
(2607005, 'Maria Hilda',     'De Leon',     'Martinez', 'SUPER',  'MAT', TRUE);


-- LINEA B
INSERT INTO empleado (numero, nombrePila, primerApell, segundoApell, rol, turno, activo) VALUES
(2607006, 'Anwar Fernando',  'Estrada',     'Santos',     'OPENSA', 'MAT', TRUE),
(2607007, 'Jesus Gildardo',  'Fonseca',     'De La Cruz', 'OPENSA', 'MAT', TRUE),
(2607008, 'Luis David',      'Gallardo',    'Ramirez',    'OPENSA', 'MAT', TRUE),
(2607009, 'Jose Jonathan',   'Gonzalez',    'De La Mora', 'OPCALI', 'MAT', TRUE),
(2607010, 'Marlene Yesenia', 'Gutierrez',   'Soto',       'SUPER',  'MAT', TRUE);


-- LINEA C
INSERT INTO empleado (numero, nombrePila, primerApell, segundoApell, rol, turno, activo) VALUES
(2607011, 'Josue Isaac',     'Huape',       'Gil',      'OPENSA', 'MAT', TRUE),
(2607012, 'Axel Santiago',   'Islas',       'Ruelas',   'OPENSA', 'MAT', TRUE),
(2607013, 'Rosalba Abigail', 'Lopez',       'Garcia',   'OPENSA', 'MAT', TRUE),
(2607014, 'Saul',            'Marquez',     'Gomez',    'OPCALI', 'MAT', TRUE),
(2607015, 'Jorge Jonathan',  'Martinez',    'Zambrano', 'SUPER',  'MAT', TRUE);


-- LINEA D
INSERT INTO empleado (numero, nombrePila, primerApell, segundoApell, rol, turno, activo) VALUES
(2607016, 'Irving De Jesus', 'Morales',     'Aparicio', 'OPENSA', 'MAT', TRUE),
(2607017, 'Hemilton Raul',   'Orduno',      'Santiago', 'OPENSA', 'MAT', TRUE),
(2607018, 'Diego',           'Sanchez',     'Hernandez','OPENSA', 'MAT', TRUE),
(2607019, 'Misael',          'Urquidez',    'Arredondo','OPCALI', 'MAT', TRUE),
(2607020, 'Fernando Alonso', 'Zuniga',      'Arevalo',  'SUPER',  'MAT', TRUE);


-- LINEA D — refuerzo para la estación de chasis inferior (D5)
-- Es la única persona que quedó de la desaparecida línea E: la que montaba el
-- chasis inferior. Los otros cuatro se dieron de baja junto con la línea.
INSERT INTO empleado (numero, nombrePila, primerApell, segundoApell, rol, turno, activo) VALUES
(2607021, 'Ana Maria',       'Antonio',     'Cova',     'OPENSA', 'MAT', TRUE);


-- LINEA E (EMBALAJE)
INSERT INTO empleado (numero, nombrePila, primerApell, segundoApell, rol, turno, activo) VALUES
(2607026, 'Anwar Fernando',  'Estrada',     'Santos',     'OPEMBA', 'MAT', TRUE),
(2607027, 'Jesus Gildardo',  'Fonseca',     'De La Cruz', 'OPEMBA', 'MAT', TRUE),
(2607028, 'Luis David',      'Gallardo',    'Ramirez',    'SUPER',  'MAT', TRUE);


-- OPERARIOS DE ENSAMBLAJE QUE CUBREN LA CUARTA ESTACIÓN
-- El inspector de calidad de cada línea se pasó a la estación de calidad (X5),
-- así que la estación X4 en la que estaba se quedó sin operario. Estos empleados
-- la cubren. Van con número nuevo al final de la secuencia para no renumerar a
-- los de arriba (datos_pruebas.sql y la tabla usuario los referencian por número).
INSERT INTO empleado (numero, nombrePila, primerApell, segundoApell, rol, turno, activo) VALUES
(2607031, 'Jose Jonathan',   'Gonzalez',    'De La Mora', 'OPENSA', 'MAT', TRUE),   -- LINEA A, EST-A4
(2607032, 'Marlene Yesenia', 'Gutierrez',   'Soto',       'OPENSA', 'MAT', TRUE),   -- LINEA B, EST-B4
(2607033, 'Josue Isaac',     'Huape',       'Gil',        'OPENSA', 'MAT', TRUE),   -- LINEA C, EST-C4
(2607034, 'Axel Santiago',   'Islas',       'Ruelas',     'OPENSA', 'MAT', TRUE);   -- LINEA D, EST-D4


-- INSPECTOR DE CALIDAD DE LA LINEA E (EMBALAJE)
-- La línea de embalaje no tenía ningún empleado con rol OPCALI al cual mover,
-- así que su estación de calidad (EST-E3) estrena inspector.
INSERT INTO empleado (numero, nombrePila, primerApell, segundoApell, rol, turno, activo) VALUES
(2607035, 'Rosalba Abigail', 'Lopez',       'Garcia',     'OPCALI', 'MAT', TRUE);   -- LINEA E, EST-E3



-- 15.1 ASIGNACION DE UN EMPLEADO A SU LINEA

INSERT INTO empleado_linea (empleado, linea, fecha_inicio, fecha_fin) VALUES
-- LINEA A (LIN001)
(2607001, 'LIN001', '2026-07-15', NULL),
(2607002, 'LIN001', '2026-07-15', NULL),
(2607003, 'LIN001', '2026-07-15', NULL),
(2607004, 'LIN001', '2026-07-15', NULL),
(2607005, 'LIN001', '2026-07-15', NULL);


-- LINEA B (LIN002)
INSERT INTO empleado_linea (empleado, linea, fecha_inicio, fecha_fin) VALUES
(2607006, 'LIN002', '2026-07-15', NULL),
(2607007, 'LIN002', '2026-07-15', NULL),
(2607008, 'LIN002', '2026-07-15', NULL),
(2607009, 'LIN002', '2026-07-15', NULL),
(2607010, 'LIN002', '2026-07-15', NULL);


-- LINEA C (LIN003)
INSERT INTO empleado_linea (empleado, linea, fecha_inicio, fecha_fin) VALUES
(2607011, 'LIN003', '2026-07-15', NULL),
(2607012, 'LIN003', '2026-07-15', NULL),
(2607013, 'LIN003', '2026-07-15', NULL),
(2607014, 'LIN003', '2026-07-15', NULL),
(2607015, 'LIN003', '2026-07-15', NULL);


-- LINEA D (LIN004) — incluye a 2607021, que llegó de la línea E con la
-- estación de chasis inferior.
INSERT INTO empleado_linea (empleado, linea, fecha_inicio, fecha_fin) VALUES
(2607016, 'LIN004', '2026-07-15', NULL),
(2607017, 'LIN004', '2026-07-15', NULL),
(2607018, 'LIN004', '2026-07-15', NULL),
(2607019, 'LIN004', '2026-07-15', NULL),
(2607020, 'LIN004', '2026-07-15', NULL),
(2607021, 'LIN004', '2026-07-15', NULL);


-- LINEA E - EMBALAJE (LIN005)
INSERT INTO empleado_linea (empleado, linea, fecha_inicio, fecha_fin) VALUES
(2607026, 'LIN005', '2026-07-15', NULL),
(2607027, 'LIN005', '2026-07-15', NULL),
(2607028, 'LIN005', '2026-07-15', NULL);


-- EMPLEADOS NUEVOS (cuartas estaciones e inspector de embalaje)
INSERT INTO empleado_linea (empleado, linea, fecha_inicio, fecha_fin) VALUES
(2607031, 'LIN001', '2026-07-15', NULL),
(2607032, 'LIN002', '2026-07-15', NULL),
(2607033, 'LIN003', '2026-07-15', NULL),
(2607034, 'LIN004', '2026-07-15', NULL),
(2607035, 'LIN005', '2026-07-15', NULL);



-- 15.2 ASIGNACION DE UN EMPLEADO A SU ESTACION

-- El empleado con rol OPCALI de cada línea va en la última estación (la de
-- calidad) y la estación anterior la cubre un operario de ensamblaje.

INSERT INTO empleado_estacion (empleado, estacion, fecha_inicio, fecha_fin) VALUES
-- LINEA A
(2607001, 'EST-A1', '2026-07-15', NULL),
(2607002, 'EST-A2', '2026-07-15', NULL),
(2607003, 'EST-A3', '2026-07-15', NULL),
(2607031, 'EST-A4', '2026-07-15', NULL),
(2607004, 'EST-A5', '2026-07-15', NULL);   -- Ricardo Daniel De La Torre Garcia (OPCALI)

-- LINEA B
INSERT INTO empleado_estacion (empleado, estacion, fecha_inicio, fecha_fin) VALUES
(2607006, 'EST-B1', '2026-07-15', NULL),
(2607007, 'EST-B2', '2026-07-15', NULL),
(2607008, 'EST-B3', '2026-07-15', NULL),
(2607032, 'EST-B4', '2026-07-15', NULL),
(2607009, 'EST-B5', '2026-07-15', NULL);   -- Jose Jonathan Gonzalez De La Mora (OPCALI)

-- LINEA C
INSERT INTO empleado_estacion (empleado, estacion, fecha_inicio, fecha_fin) VALUES
(2607011, 'EST-C1', '2026-07-15', NULL),
(2607012, 'EST-C2', '2026-07-15', NULL),
(2607013, 'EST-C3', '2026-07-15', NULL),
(2607033, 'EST-C4', '2026-07-15', NULL),
(2607014, 'EST-C5', '2026-07-15', NULL);   -- Saul Marquez Gomez (OPCALI)

-- LINEA D
INSERT INTO empleado_estacion (empleado, estacion, fecha_inicio, fecha_fin) VALUES
(2607016, 'EST-D1', '2026-07-15', NULL),
(2607017, 'EST-D2', '2026-07-15', NULL),
(2607018, 'EST-D3', '2026-07-15', NULL),
(2607034, 'EST-D4', '2026-07-15', NULL),
(2607021, 'EST-D5', '2026-07-15', NULL),   -- Ana Maria Antonio Cova, venía de la línea E
(2607019, 'EST-D6', '2026-07-15', NULL);   -- Misael Urquidez Arredondo (OPCALI)

-- LINEA E (EMBALAJE)
INSERT INTO empleado_estacion (empleado, estacion, fecha_inicio, fecha_fin) VALUES
(2607026, 'EST-E1', '2026-07-15', NULL),
(2607027, 'EST-E2', '2026-07-15', NULL),
(2607035, 'EST-E3', '2026-07-15', NULL);   -- Rosalba Abigail Lopez Garcia (OPCALI)




########33PRUEBA PARA EL LOGIN

-- Los dos empleados administradores. Los demás usuarios de más abajo se cuelgan
-- de empleados que ya se dieron de alta arriba.

INSERT INTO empleado (numero, nombrePila, primerApell, segundoApell,rol,turno, activo)
VALUES (
    2607029, 'Araceli', 'Marcos', 'Montes', 'ADMIN','MAT', TRUE);

INSERT INTO empleado (numero, nombrePila, primerApell, segundoApell,rol,turno, activo)
VALUES (
    2607030, 'Salvador', 'Garcia', 'Bojorquez', 'ADMIN','MAT', TRUE);


-- ============================================================================
-- 17. USUARIOS
-- ============================================================================
--
-- IMPORTANTE: las contraseñas aquí van EN TEXTO PLANO, a propósito, para que se
-- puedan leer y cambiar sin pelearse con un hash.
--
-- Así NO sirven para entrar: LoginAPIView compara con `check_password`, que
-- espera un hash de Django. Después de correr este archivo hay que ejecutar:
--
--     python DB/encriptar_contrasenas.py
--
-- Ese script recorre la tabla y reemplaza cada contraseña en texto plano por su
-- hash PBKDF2. Es idempotente: lo que ya está hasheado lo deja igual, así que
-- puedes correrlo las veces que quieras.
--
-- Convención de usuario: 4 dígitos de secuencia + iniciales de nombre y apellidos
-- (0001AMM = Araceli Marcos Montes).
--
-- Los usuarios de calidad y supervisor NO dan de alta empleados nuevos: se
-- cuelgan de empleados que ya existen arriba con ese rol y que ya están
-- asignados a una línea (ver empleado_linea). Eso importa para calidad, porque
-- el formulario de inspecciones llena su select de inspectores por línea.
--
-- OJO: son credenciales de desarrollo y este archivo está en el repositorio, así
-- que son públicas. No las lleves a un ambiente real.


-- ---------------------------------------------------------------- ADMIN
-- Ven todo y entran a /panel/admin/

INSERT INTO usuario (usuario,contrasena,estado,empleado) VALUES
('0001AMM',  '12345',   1, 2607029),   -- Araceli Marcos Montes
('rodavlas', '172509',  1, 2607030);   -- Salvador Garcia Bojorquez


-- ------------------------------------------------- OPERADORES DE CALIDAD
-- Rol OPCALI, entran a /panel/calidad/
-- Contraseña = las 3 letras del usuario + 2026

INSERT INTO usuario (usuario,contrasena,estado,empleado) VALUES
('0002RTG', 'RTG2026', 1, 2607004),   -- Ricardo Daniel De La Torre Garcia (LINEA A)
('0004JGM', 'JGM2026', 1, 2607009),   -- Jose Jonathan Gonzalez De La Mora (LINEA B)
('0006SMG', 'SMG2026', 1, 2607014),   -- Saul Marquez Gomez                (LINEA C)
('0008MUA', 'MUA2026', 1, 2607019),   -- Misael Urquidez Arredondo         (LINEA D)
('0013RLG', 'RLG2026', 1, 2607035);   -- Rosalba Abigail Lopez Garcia      (LINEA E, embalaje)


-- -------------------------------------------------------------- SUPERVISORES
-- Rol SUPER, entran a /panel/supervisor/
-- Contraseña = las 3 letras del usuario + 2026

INSERT INTO usuario (usuario,contrasena,estado,empleado) VALUES
('0003MDM', 'MDM2026', 1, 2607005),   -- Maria Hilda De Leon Martinez     (LINEA A)
('0005MGS', 'MGS2026', 1, 2607010),   -- Marlene Yesenia Gutierrez Soto   (LINEA B)
('0007JMZ', 'JMZ2026', 1, 2607015),   -- Jorge Jonathan Martinez Zambrano (LINEA C)
('0009FZA', 'FZA2026', 1, 2607020),   -- Fernando Alonso Zuniga Arevalo   (LINEA D)
('0012LGR', 'LGR2026', 1, 2607028);   -- Luis David Gallardo Ramirez      (LINEA E, embalaje)



SET FOREIGN_KEY_CHECKS = 1;