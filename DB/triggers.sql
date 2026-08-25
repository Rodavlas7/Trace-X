-- TRACEX — Triggers
-- Version: 2026-08-19
--
--
-- CÓMO ESTÁ ORGANIZADO
-- --------------------
-- Un trigger por (tabla, momento, evento). MySQL permite varios sobre el mismo
-- evento y los corre en orden de creación, pero eso deja el orden escondido en
-- el orden del archivo: no se ve al leer un trigger, y un `information_schema`
-- es la única forma de comprobarlo. Aquí las reglas que comparten evento están
-- dentro del mismo BEGIN...END, en el orden en que tienen que pasar, y ese
-- orden se lee de arriba abajo.
--
-- Antes eran 17 triggers; son 11 con la misma lógica. Lo que se juntó:
--
--   AFTER INSERT laptop            3 -> 1   tg_Laptop_Alta
--   AFTER UPDATE laptop            2 -> 1   tg_Laptop_Cambio
--   BEFORE INSERT reg_ensamblaje   3 -> 1   tg_Validar_Apertura_Ensamblaje
--   AFTER INSERT reg_embalaje      2 -> 1   tg_Registrar_Embalaje
--
-- Los otros siete conservan su nombre porque no se fusionaron con nada, y así
-- la documentación que ya los menciona sigue sirviendo.
--
--
-- OJO CON EL LARGO DE LOS MENSAJES
-- --------------------------------
-- MESSAGE_TEXT admite 128 caracteres. Si un mensaje se pasa, MySQL no lanza el
-- 1644 con el motivo redactado, sino un 1648 'Data too long for condition
-- item'. La operación igual se cancela, pero api/errores.py ya no reconoce el
-- código y en pantalla sale "La base de datos rechazó la operación" en lugar de
-- la explicación. Deja holgura: el prefijo 'Error tg_Nombre: ' ya se come una
-- buena parte.


USE cuatro;


DROP TRIGGER IF EXISTS tg_Arrancar_Laptop_En_Ensamblaje;
DROP TRIGGER IF EXISTS tg_Laptop_Alta;
DROP TRIGGER IF EXISTS tg_Generar_Numero_Serie_Final;
DROP TRIGGER IF EXISTS tg_Laptop_Cambio;
DROP TRIGGER IF EXISTS tg_Sincronizar_Cant_Producida_Baja;
DROP TRIGGER IF EXISTS tg_Validar_Apertura_Ensamblaje;
DROP TRIGGER IF EXISTS tg_Validar_Linea_Ensamblaje_Cambio;
DROP TRIGGER IF EXISTS tg_Actualizar_Estado_Laptop_Inspeccion_Calidad;
DROP TRIGGER IF EXISTS tg_Registrar_Embalaje;
DROP TRIGGER IF EXISTS tg_Validar_Capacidad_Componente;
DROP TRIGGER IF EXISTS tg_Validar_Capacidad_Componente_Cambio;
DROP TRIGGER IF EXISTS tg_Validar_Compatibilidad_Componente;
DROP TRIGGER IF EXISTS tg_Validar_Compatibilidad_Componente_Cambio;
DROP TRIGGER IF EXISTS tg_Validar_Compatibilidad_Detalle_Material;
DROP TRIGGER IF EXISTS tg_Validar_Compatibilidad_Detalle_Material_Cambio;
DROP TRIGGER IF EXISTS tg_Validar_Compatibilidad_Detalle_Material_Baja;
DROP TRIGGER IF EXISTS tg_Iniciar_Orden_Al_Registrar_Laptop;
DROP TRIGGER IF EXISTS tg_Sincronizar_Cant_Producida_Alta;
DROP TRIGGER IF EXISTS tg_Abrir_Ensamblaje_Primera_Linea;
DROP TRIGGER IF EXISTS tg_Iniciar_Orden_Al_Mover_Laptop;
DROP TRIGGER IF EXISTS tg_Sincronizar_Cant_Producida_Cambio;
DROP TRIGGER IF EXISTS tg_Bloquear_Componentes_Laptop_Finalizada;
DROP TRIGGER IF EXISTS tg_Control_Componentes_Duplicados;
DROP TRIGGER IF EXISTS tg_Validar_Linea_Ensamblaje;
DROP TRIGGER IF EXISTS tg_Control_Estado_Orden_Produccion;
DROP TRIGGER IF EXISTS tg_Finalizar_Proceso_Embalaje;

DELIMITER $$


-- ============================================================================
-- L A P T O P
-- ============================================================================


-- ----------------------------------------------------------------------------
-- tg_Arrancar_Laptop_En_Ensamblaje        BEFORE INSERT ON laptop
-- ----------------------------------------------------------------------------
-- Que el reloj del ensamblaje empiece a correr en el momento en que la laptop
-- se registra. Nace 'En Ensamblaje' (PENSAM), no 'Registrada'.
--
-- Consecuencia a tener presente: REGIS deja de ser un estado en el que una
-- laptop se quede.
--
-- Va aparte de tg_Laptop_Alta porque es BEFORE: aquí todavía se puede tocar
-- NEW, y en el AFTER ya no. Ese SET NEW.estado es justamente lo que evita el
-- error 1442 —un trigger no puede hacer UPDATE de la tabla que lo disparó—.

CREATE TRIGGER tg_Arrancar_Laptop_En_Ensamblaje
BEFORE INSERT ON laptop
FOR EACH ROW
BEGIN
    IF NEW.estado IS NULL OR NEW.estado = 'REGIS' THEN
        SET NEW.estado = 'PENSAM';
    END IF;
END$$


-- ----------------------------------------------------------------------------
-- tg_Laptop_Alta                          AFTER INSERT ON laptop
-- ----------------------------------------------------------------------------
-- Todo lo que pasa al dar de alta una laptop, en este orden:
--
--   1. La orden arranca. Si estaba 'Pendiente' pasa a 'En Proceso': ya se está
--      trabajando en ella. Una Cancelada o Completada no se reabre.
--   2. Se les aplican sus deltas a cant_producida y a cant_rechazada.
--   3. Se le abre su registro de ensamblaje en la primera línea.
--
-- El orden importa y por eso están juntos: el paso 3 inserta en
-- registro_ensamblaje y dispara los validadores de esa tabla, así que va al
-- final, cuando la laptop ya quedó consistente.
--
-- Las dos cantidades de la orden se llevan por fórmula, sumando y restando:
-- cada trigger aplica el delta de la laptop que tocó en vez de barrer la orden
-- completa. cant_producida cuenta las que ya terminaron —'APROV' y 'EMBALA'— y
-- cant_rechazada las que calidad tiró, que es el desperdicio de la orden.
--
-- Las dos se guardan en la orden en lugar de calcularse en la vista porque la
-- pantalla de producción las lee en cada renglón de la lista, y así salen del
-- mismo SELECT que ya trae la orden, sin subconsulta por renglón.
--
-- Para que un contador incremental no se despegue de la realidad, el delta
-- tiene que estar en todas las vías por las que una laptop puede moverlo, y
-- ahí está: el alta, el cambio de estado, el cambio de orden y la baja. Lo que
-- queda fuera es lo que se toque por fuera de los triggers, y para eso está el
-- UPDATE de SINCRONIZACIÓN INICIAL del final del archivo, que recuadra las dos
-- columnas de un jalón.
--
-- Cada término es IFNULL(<la condición>, 0) y vale 1 o 0. El IFNULL no sobra:
-- `estado` admite nulos y NULL IN (...) no da 0, da NULL, que echaría a perder
-- la suma entera. El de la columna es por lo mismo.
--
-- El paso de 'APROV' a 'EMBALA' no mueve cant_producida: los dos términos valen
-- 1 y el delta sale 0. Por eso embalar no la infla.
--
-- Cuál es "la primera línea" no se escribe a mano: es la línea de ensamblaje a
-- la que ninguna otra apunta con `siguiente`. Si se reordena la cadena, esto
-- sigue solo. El resto de las líneas no necesita esto: su registro lo abre el
-- relevo de tg_Actualizar_Estado_Laptop_Inspeccion_Calidad.
--
-- (Fusiona tg_Iniciar_Orden_Al_Registrar_Laptop, tg_Sincronizar_Cant_Producida_Alta
--  y tg_Abrir_Ensamblaje_Primera_Linea.)

CREATE TRIGGER tg_Laptop_Alta
AFTER INSERT ON laptop
FOR EACH ROW
BEGIN
    DECLARE primera_linea VARCHAR(8) DEFAULT NULL;

    IF NEW.orden IS NOT NULL THEN

        -- 1. Arrancar la orden
        UPDATE orden_produccion
           SET estado = 'PROC'
         WHERE folio  = NEW.orden
           AND estado = 'PEND';

        -- 2. Sumar lo que traiga esta laptop. Normalmente nace 'En
        --    Ensamblaje' y los dos términos valen 0; una carga de datos que la
        --    meta ya terminada o ya rechazada sí suma.
        UPDATE orden_produccion
           SET cant_producida = IFNULL(cant_producida, 0)
                                + IFNULL(NEW.estado IN ('APROV', 'EMBALA'), 0),
               cant_rechazada = IFNULL(cant_rechazada, 0)
                                + IFNULL(NEW.estado = 'RECHA', 0)
         WHERE folio = NEW.orden;

    END IF;

    -- 3. Abrir el ensamblaje de la primera línea.
    --    Sólo a la que nace para producirse: una carga de datos que dé de alta
    --    una laptop ya aprobada o embalada no tiene por qué estrenar ensamblaje.
    IF NEW.estado = 'PENSAM' THEN

        SELECT l.codigo
          INTO primera_linea
          FROM linea l
         WHERE l.tipo = 'ENSA'
           AND NOT EXISTS (SELECT 1 FROM linea p WHERE p.siguiente = l.codigo)
         ORDER BY l.codigo
         LIMIT 1;

        IF primera_linea IS NOT NULL THEN
            INSERT INTO registro_ensamblaje (fecha_inicio, hora_inicio, laptop, linea)
            VALUES (CURDATE(), CURTIME(), NEW.numero, primera_linea);
        END IF;

    END IF;
END$$


-- ----------------------------------------------------------------------------
-- tg_Generar_Numero_Serie_Final           BEFORE UPDATE ON laptop
-- ----------------------------------------------------------------------------
-- El número de serie definitivo, cuando la laptop pasa a 'Aprobada':
--
--     TP-{AAAAMMDD}-{numero de laptop a 6 dígitos}     TP-20260813-000034
--
-- Es BEFORE UPDATE y asigna con SET NEW. Siendo AFTER habría que hacer un
-- UPDATE de laptop dentro de un trigger de laptop, y eso es el error 1442.
--
-- OLD.estado se compara con IS NULL / <> porque la columna admite nulos y
-- 'NULL <> APROV' no es TRUE, es NULL: la condición nunca se cumpliría para una
-- laptop que venía sin estado.
--
-- Acepta reemplazar una serie provisional 'TMP-%', que es la que ponen
-- sp_Iniciar_Ensamblaje_Orden y el alta desde el cliente.

CREATE TRIGGER tg_Generar_Numero_Serie_Final
BEFORE UPDATE ON laptop
FOR EACH ROW
BEGIN
    IF NEW.estado = 'APROV'
       AND (OLD.estado IS NULL OR OLD.estado <> 'APROV')
       AND (NEW.num_serie IS NULL OR NEW.num_serie = '' OR NEW.num_serie LIKE 'TMP-%')
    THEN
        SET NEW.num_serie = CONCAT(
            'TP-',
            DATE_FORMAT(CURDATE(), '%Y%m%d'),
            '-',
            LPAD(NEW.numero, 6, '0')
        );
    END IF;
END$$


-- ----------------------------------------------------------------------------
-- tg_Laptop_Cambio                        AFTER UPDATE ON laptop
-- ----------------------------------------------------------------------------
-- Las dos cosas que hay que rehacer cuando una laptop cambia:
--
--   1. Si la reasignaron a otra orden y esa estaba 'Pendiente', arranca. Es el
--      mismo arranque que hace tg_Laptop_Alta, pero por la otra vía: la pantalla
--      de edición deja cambiar la orden, y por ahí una orden Pendiente recibía
--      su primera laptop sin arrancar.
--   2. Se aplican los deltas de cant_producida y cant_rechazada. Si se movió
--      de orden se tocan las dos: la que la recibe y la que la pierde. Ahí está
--      el caso fino de la fórmula — cuando la laptop se queda en su orden el
--      delta es la diferencia (es_algo - era_algo); cuando cambia de orden, la
--      de destino se la suma entera y la de origen se la resta entera, porque
--      para cada una es una laptop que llega o que se va, no una que cambia.
--
-- La orden que PIERDE la laptop no regresa a 'Pendiente'. Sería adivinar: pudo
-- avanzar a 'En Proceso' por otras razones, y una orden que retrocede sola
-- confunde más de lo que ayuda.
--
-- El operador <=> compara tolerando nulos, cosa que '=' no hace: con '=' una
-- laptop que pasa de NULL a una orden no se detectaría.
--
-- Se dispara mucho —los UPDATE de laptop de los triggers de inspección y
-- embalaje pasan por aquí— y casi siempre sólo aplica el delta del estado,
-- porque la columna `orden` no cambia en esos casos.
--
-- (Fusiona tg_Iniciar_Orden_Al_Mover_Laptop y tg_Sincronizar_Cant_Producida_Cambio.)

CREATE TRIGGER tg_Laptop_Cambio
AFTER UPDATE ON laptop
FOR EACH ROW
BEGIN
    -- Los términos de las dos fórmulas: cómo contaba la laptop antes del
    -- UPDATE y cómo cuenta después. Cada uno vale 1 o 0.
    DECLARE era_prod  INT DEFAULT 0;
    DECLARE es_prod   INT DEFAULT 0;
    DECLARE era_recha INT DEFAULT 0;
    DECLARE es_recha  INT DEFAULT 0;

    SET era_prod  = IFNULL(OLD.estado IN ('APROV', 'EMBALA'), 0);
    SET es_prod   = IFNULL(NEW.estado IN ('APROV', 'EMBALA'), 0);
    SET era_recha = IFNULL(OLD.estado = 'RECHA', 0);
    SET es_recha  = IFNULL(NEW.estado = 'RECHA', 0);

    -- 1. Arrancar la orden nueva, sólo si de verdad cambió de orden
    IF NOT (NEW.orden <=> OLD.orden) AND NEW.orden IS NOT NULL THEN
        UPDATE orden_produccion
           SET estado = 'PROC'
         WHERE folio  = NEW.orden
           AND estado = 'PEND';
    END IF;

    -- 2. Recontar y aplicar deltas. Sólo interesan los cambios de estado o de
    --    orden: los demás UPDATE de laptop no mueven ninguno de los dos números.
    IF NOT (NEW.estado <=> OLD.estado) OR NOT (NEW.orden <=> OLD.orden) THEN


        IF NEW.orden IS NOT NULL THEN
            UPDATE orden_produccion
               SET cant_producida = IFNULL(cant_producida, 0)
                                    + es_prod
                                    - IF(NEW.orden <=> OLD.orden, era_prod, 0),
                   cant_rechazada = IFNULL(cant_rechazada, 0)
                                    + es_recha
                                    - IF(NEW.orden <=> OLD.orden, era_recha, 0)
             WHERE folio = NEW.orden;
        END IF;

        IF OLD.orden IS NOT NULL AND NOT (OLD.orden <=> NEW.orden) THEN
            UPDATE orden_produccion
               SET cant_producida = IFNULL(cant_producida, 0) - era_prod,
                   cant_rechazada = IFNULL(cant_rechazada, 0) - era_recha
             WHERE folio = OLD.orden;
        END IF;

    END IF;
END$$


-- ----------------------------------------------------------------------------
-- tg_Sincronizar_Cant_Producida_Baja      AFTER DELETE ON laptop
-- ----------------------------------------------------------------------------
-- El mismo delta al revés, cuando se borra una laptop: la que se va deja de
-- contar en la columna que le tocaba. Va solo porque es el único trigger de
-- DELETE sobre la tabla.

CREATE TRIGGER tg_Sincronizar_Cant_Producida_Baja
AFTER DELETE ON laptop
FOR EACH ROW
BEGIN
    IF OLD.orden IS NOT NULL THEN
        UPDATE orden_produccion
           SET cant_producida = IFNULL(cant_producida, 0)
                                - IFNULL(OLD.estado IN ('APROV', 'EMBALA'), 0),
               cant_rechazada = IFNULL(cant_rechazada, 0)
                                - IFNULL(OLD.estado = 'RECHA', 0)
         WHERE folio = OLD.orden;
    END IF;
END$$


-- ============================================================================
-- R E G I S T R O   D E   E N S A M B L A J E
-- ============================================================================


-- ----------------------------------------------------------------------------
-- tg_Validar_Apertura_Ensamblaje          BEFORE INSERT ON registro_ensamblaje
-- ----------------------------------------------------------------------------
-- Las tres condiciones para poder abrirle un ensamblaje a una laptop. Van en
-- este orden, y el primer SIGNAL corta:
--
--   1. La línea existe y es de ensamblaje.
--   2. La laptop no terminó su proceso productivo.
--   3. La laptop no tiene ya un ensamblaje abierto, ni recorrió la última línea.
--
-- El orden es a propósito: primero lo que es un dato mal capturado (la línea) y
-- después el estado de la laptop, que es lo que le importa al operador. Antes
-- eran tres triggers y el orden lo decidía el orden del archivo, cosa que no se
-- veía al leerlos.
--
-- Sobre la línea: ENSA se arma, EMBA se empaca. Un registro de ensamblaje
-- contra una línea de embalaje no es un descuido de captura, es una laptop que
-- quedaría trazada en un proceso que no existe ahí, surtiéndose de un stock que
-- no le toca. La API y el cliente ya filtran las líneas, pero ésta es la única
-- barrera que también cubre a quien escriba por SQL o por otro cliente.
--
-- Sobre los duplicados, la regla cuida dos cosas:
--   a. Una laptop no puede tener dos registros ABIERTOS a la vez. Estaría en dos
--      líneas al mismo tiempo, y el checklist no sabría a cuál sumarle piezas.
--   b. Una laptop que ya cerró el registro de la ÚLTIMA línea de ensamblaje
--      terminó de armarse: no se le abre otro.
--   La última línea se deduce de la cadena, igual que la primera: es la de tipo
--   ENSA cuya siguiente ya no es de ensamblaje.
--
-- (Fusiona tg_Validar_Linea_Ensamblaje, tg_Bloquear_Componentes_Laptop_Finalizada
--  y tg_Control_Componentes_Duplicados.)

CREATE TRIGGER tg_Validar_Apertura_Ensamblaje
BEFORE INSERT ON registro_ensamblaje
FOR EACH ROW
BEGIN
    DECLARE tipo_de_linea     VARCHAR(8) DEFAULT NULL;
    DECLARE estado_laptop   VARCHAR(8) DEFAULT NULL;
    DECLARE ensamblajes_abiertos INT DEFAULT 0;
    DECLARE ultima_linea   VARCHAR(8) DEFAULT NULL;
    DECLARE registros_ultima_linea  INT DEFAULT 0;

    -- 1. La línea
    IF NEW.linea IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Apertura: el registro de ensamblaje necesita una línea';
    END IF;

    SELECT tipo INTO tipo_de_linea FROM linea WHERE codigo = NEW.linea;

    IF tipo_de_linea IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Apertura: esa línea no tiene tipo asignado, no se puede ensamblar en ella';
    END IF;

    IF tipo_de_linea <> 'ENSA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Apertura: solo se puede registrar ensamblaje en líneas de tipo Ensamblaje';
    END IF;

    -- 2. El estado de la laptop
    SELECT estado INTO estado_laptop FROM laptop WHERE numero = NEW.laptop;

    IF estado_laptop IN ('APROV', 'RECHA', 'EMBALA') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Apertura: la laptop ya finalizó su proceso productivo';
    END IF;

    -- 3. Que no haya otro abierto
    SELECT COUNT(*)
      INTO ensamblajes_abiertos
      FROM registro_ensamblaje
     WHERE laptop    = NEW.laptop
       AND fecha_fin IS NULL;

    IF ensamblajes_abiertos > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Apertura: la laptop ya tiene un ensamblaje abierto, ciérralo primero';
    END IF;

    -- ...y que no haya terminado ya el recorrido
    SELECT l.codigo
      INTO ultima_linea
      FROM linea l
     WHERE l.tipo = 'ENSA'
       AND NOT EXISTS (SELECT 1 FROM linea s
                        WHERE s.codigo = l.siguiente AND s.tipo = 'ENSA')
     ORDER BY l.codigo DESC
     LIMIT 1;

    IF ultima_linea IS NOT NULL THEN
        SELECT COUNT(*)
          INTO registros_ultima_linea
          FROM registro_ensamblaje
         WHERE laptop    = NEW.laptop
           AND linea     = ultima_linea
           AND fecha_fin IS NOT NULL;

        IF registros_ultima_linea > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Apertura: la laptop ya recorrió todas las líneas de ensamblaje';
        END IF;
    END IF;
END$$


-- ----------------------------------------------------------------------------
-- tg_Validar_Linea_Ensamblaje_Cambio      BEFORE UPDATE ON registro_ensamblaje
-- ----------------------------------------------------------------------------
-- La misma regla de la línea, para cuando se mueve un registro ya creado.
--
-- Sólo revisa cuando la línea de verdad cambia: cerrar un ensamblaje pone
-- fecha_fin/hora_fin y no tiene por qué volver a validar nada. Las otras dos
-- condiciones del alta no aplican aquí: el registro ya existe, y cerrarlo es
-- precisamente lo que hace la inspección sobre una laptop que sigue en proceso.

CREATE TRIGGER tg_Validar_Linea_Ensamblaje_Cambio
BEFORE UPDATE ON registro_ensamblaje
FOR EACH ROW
BEGIN
    DECLARE tipo_de_linea VARCHAR(8) DEFAULT NULL;

    IF NOT (NEW.linea <=> OLD.linea) THEN

        IF NEW.linea IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Linea_Cambio: el registro de ensamblaje necesita una línea';
        END IF;

        SELECT tipo INTO tipo_de_linea FROM linea WHERE codigo = NEW.linea;

        IF tipo_de_linea IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Linea_Cambio: esa línea no tiene tipo asignado, no se puede ensamblar en ella';
        END IF;

        IF tipo_de_linea <> 'ENSA' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Linea_Cambio: solo se puede registrar ensamblaje en líneas de tipo Ensamblaje';
        END IF;

    END IF;
END$$


-- ============================================================================
-- I N S P E C C I Ó N   D E   C A L I D A D
-- ============================================================================


-- ----------------------------------------------------------------------------
-- tg_Actualizar_Estado_Laptop_Inspeccion_Calidad
--                                         AFTER INSERT ON inspeccion_calidad
-- ----------------------------------------------------------------------------
-- El corazón del recorrido por líneas. Cada línea de ensamblaje cierra con su
-- estación de calidad, así que una laptop pasa por CUATRO inspecciones: aprobar
-- en la A no significa que esté terminada, sólo que puede pasar a la B. Aprobar
-- en la última sí es la aprobación final.
--
-- El inspector no elige entre "pasa de línea" y "aprobada final": marca Aprobada
-- o Rechazada y aquí se deduce cuál de las dos es, mirando si la línea donde se
-- inspeccionó tiene una siguiente de ensamblaje.
--
--   Aprobada, con línea siguiente  -> cierra el registro de esta línea y abre el
--                                     de la siguiente. La laptop sigue PENSAM.
--   Aprobada, última línea         -> cierra el registro. La laptop pasa a APROV
--                                     y tg_Generar_Numero_Serie_Final le pone su
--                                     número de serie definitivo.
--   Rechazada                      -> cierra el registro y la laptop pasa a
--                                     RECHA. No se abre nada más: sale de línea.
--   Continuar ensamblaje (2)       -> no cierra nada. Es la salida para cuando
--                                     la inspección no concluye y la laptop se
--                                     queda en la misma línea.
--
-- Concentra los tres efectos porque es el único lugar donde MySQL deja hacerlos
-- juntos: corre sobre inspeccion_calidad, así que puede tocar laptop y
-- registro_ensamblaje sin chocar con el error 1442. Poner el relevo en un AFTER
-- UPDATE de registro_ensamblaje NO es posible: ese trigger tendría que insertar
-- en su propia tabla.

CREATE TRIGGER tg_Actualizar_Estado_Laptop_Inspeccion_Calidad
AFTER INSERT ON inspeccion_calidad
FOR EACH ROW
BEGIN
    DECLARE estado_laptop VARCHAR(8);
    DECLARE linea_siguiente VARCHAR(8) DEFAULT NULL;
    DECLARE ensamblaje_abierto INT DEFAULT 0;

    SELECT estado
      INTO estado_laptop
      FROM laptop
     WHERE numero = NEW.laptop;

    IF estado_laptop = 'PENSAM' THEN

        IF NEW.resultado NOT IN (0, 1, 2) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Inspeccion_Calidad: resultado de inspección no válido';
        END IF;

        IF NEW.resultado IN (0, 1) THEN

            -- Tiene que haber un ensamblaje abierto DE ESA LÍNEA. Si no lo hay,
            -- la inspección se está capturando donde no toca y cerrarla en falso
            -- dejaría a la laptop atorada sin registro ni relevo.
            SELECT COUNT(*)
              INTO ensamblaje_abierto
              FROM registro_ensamblaje
             WHERE laptop    = NEW.laptop
               AND linea     = NEW.linea
               AND fecha_fin IS NULL;

            IF ensamblaje_abierto = 0 THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'Error tg_Inspeccion_Calidad: la laptop no tiene un ensamblaje abierto en esa línea';
            END IF;

            -- Sella el fin del ensamblaje de esta línea.
            UPDATE registro_ensamblaje
               SET fecha_fin = CURDATE(),
                   hora_fin  = CURTIME()
             WHERE laptop    = NEW.laptop
               AND linea     = NEW.linea
               AND fecha_fin IS NULL;

        END IF;

        IF NEW.resultado = 0 THEN

            UPDATE laptop SET estado = 'RECHA' WHERE numero = NEW.laptop;

        ELSEIF NEW.resultado = 1 THEN

            -- La siguiente línea sólo cuenta si es de ensamblaje: la cadena
            -- termina donde empieza el embalaje.
            SELECT l.siguiente
              INTO linea_siguiente
              FROM linea l
             WHERE l.codigo = NEW.linea
               AND EXISTS (SELECT 1 FROM linea s
                            WHERE s.codigo = l.siguiente AND s.tipo = 'ENSA');

            IF linea_siguiente IS NOT NULL THEN
                -- Relevo: la laptop sigue en ensamblaje, ahora en la que sigue.
                INSERT INTO registro_ensamblaje (fecha_inicio, hora_inicio, laptop, linea)
                VALUES (CURDATE(), CURTIME(), NEW.laptop, linea_siguiente);
            ELSE
                -- Era la última línea: aprobación final.
                UPDATE laptop SET estado = 'APROV' WHERE numero = NEW.laptop;
            END IF;

        END IF;

    ELSEIF estado_laptop IN ('APROV', 'RECHA', 'EMBALA') THEN

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Inspeccion_Calidad: la laptop ya finalizó el proceso de inspección';

    ELSE

        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Inspeccion_Calidad: la laptop no está en estado de ensamblaje para ser inspeccionada';

    END IF;

END$$


-- ============================================================================
-- R E G I S T R O   D E   E M B A L A J E
-- ============================================================================


-- ----------------------------------------------------------------------------
-- tg_Registrar_Embalaje                   AFTER INSERT ON registro_embalaje
-- ----------------------------------------------------------------------------
-- Lo que pasa cuando una laptop se embala, en este orden:
--
--   1. La laptop pasa a 'Embalada'. Si no venía de 'Aprobada', se cancela todo
--      con un motivo en lugar de actualizar en silencio.
--   2. Se mira la orden: si ya se embalaron todas las planificadas queda
--      'Completada'.
--
-- Que el paso 1 vaya primero es lo que permite que el 2 cuente derecho. Cuando
-- eran dos triggers, el del estado de la orden corría ANTES del que marca la
-- laptop, y tenía que contar `estado = 'EMBALA' OR numero = NEW.laptop` para
-- incluir a la que se estaba embalando en ese momento. Juntos, el conteo es el
-- conteo y ya.
--
-- La rama 'PEND' -> 'PROC' casi nunca se cumple: para cuando se embala algo, la
-- orden ya arrancó con tg_Laptop_Alta. Se conserva para la orden que alguien
-- regresó a Pendiente a mano.
--
-- Una orden Cancelada o Completada no se toca.
--
-- (Fusiona tg_Finalizar_Proceso_Embalaje y tg_Control_Estado_Orden_Produccion.)

CREATE TRIGGER tg_Registrar_Embalaje
AFTER INSERT ON registro_embalaje
FOR EACH ROW
BEGIN
    DECLARE estado_laptop VARCHAR(8);
    DECLARE folio_orden   INT;
    DECLARE total_planificadas  INT;
    DECLARE total_embaladas     INT;
    DECLARE estado_orden  VARCHAR(8);

    -- 1. La laptop
    SELECT estado
      INTO estado_laptop
      FROM laptop
     WHERE numero = NEW.laptop;

    IF estado_laptop = 'EMBALA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Registrar_Embalaje: la laptop ya fue embalada previamente';
    END IF;

    IF estado_laptop IS NULL OR estado_laptop <> 'APROV' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Registrar_Embalaje: la laptop debe estar Aprobada para embalarse';
    END IF;

    UPDATE laptop
       SET estado = 'EMBALA'
     WHERE numero = NEW.laptop;

    -- 2. La orden
    SELECT orden INTO folio_orden FROM laptop WHERE numero = NEW.laptop;

    SELECT estado, cant_planificada
      INTO estado_orden, total_planificadas
      FROM orden_produccion
     WHERE folio = folio_orden;

    IF estado_orden IN ('PEND', 'PROC') THEN

        SELECT COUNT(*)
          INTO total_embaladas
          FROM laptop
         WHERE orden  = folio_orden
           AND estado = 'EMBALA';

        IF total_planificadas > 0 AND total_embaladas >= total_planificadas THEN
            UPDATE orden_produccion
               SET estado = 'COMP'
             WHERE folio  = folio_orden;

        ELSEIF estado_orden = 'PEND' THEN
            UPDATE orden_produccion
               SET estado = 'PROC'
             WHERE folio  = folio_orden;
        END IF;

    END IF;
END$$


-- ============================================================================
-- C O M P O N E N T E
-- ============================================================================
--
-- Los dos primeros validan lo mismo —que no se monten en una laptop más piezas de un
-- tipo de las que permite el BOM del modelo— pero sobre eventos distintos, y
-- MySQL nunca dispara uno por el otro:
--
--   _Componente         BEFORE INSERT — la pieza se crea ya asignada. Es el
--                       camino de Componentes › Nuevo componente con el campo
--                       de registro de ensamblaje lleno.
--   _Componente_Cambio  BEFORE UPDATE  — la pieza ya estaba en el stock de la
--                       línea y el checklist se la asigna. Es el camino de todos
--                       los días.
--
-- La capacidad sale del BOM (modelo_laptop_componente) del modelo de la laptop.
-- Se cuentan las piezas del MISMO tipo ya instaladas, excluyendo las mermadas
-- (EDC004), que liberan espacio. Si el tipo no está en el BOM, no es compatible
-- con el modelo y se bloquea.
--
-- Comparten unas 25 líneas de lógica. Se podrían sacar a una FUNCTION que ambos
-- llamen; se dejaron aquí para no meter un objeto más en la base.


CREATE TRIGGER tg_Validar_Capacidad_Componente
BEFORE INSERT ON componente
FOR EACH ROW
BEGIN
    DECLARE numero_laptop        INT;
    DECLARE modelo_de_laptop VARCHAR(8);
    DECLARE tipo_de_componente          VARCHAR(8);
    DECLARE capacidad_permitida     INT;
    DECLARE total_instalados    INT;

    -- Si es inventario libre (sin ensamblaje), no hay nada que validar.
    IF NEW.registro_ensamblaje IS NOT NULL AND NEW.modelo IS NOT NULL THEN

        SELECT re.laptop, l.modelo
          INTO numero_laptop, modelo_de_laptop
          FROM registro_ensamblaje re
          JOIN laptop l ON l.numero = re.laptop
         WHERE re.numero = NEW.registro_ensamblaje;

        SELECT mc.tipo_componente
          INTO tipo_de_componente
          FROM modelo_componente mc
         WHERE mc.codigo = NEW.modelo;

        SELECT MAX(mlc.capacidad)
          INTO capacidad_permitida
          FROM modelo_laptop_componente mlc
          JOIN modelo_componente mc2 ON mc2.codigo = mlc.modelo_componente
         WHERE mlc.modelo_laptop   = modelo_de_laptop
           AND mc2.tipo_componente = tipo_de_componente;

        IF capacidad_permitida IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Capacidad_Componente: el tipo de componente no es compatible con el modelo de la laptop';
        END IF;

        SELECT COUNT(*)
          INTO total_instalados
          FROM componente c
          JOIN registro_ensamblaje re2 ON re2.numero = c.registro_ensamblaje
          JOIN modelo_componente   mc3 ON mc3.codigo = c.modelo
         WHERE re2.laptop          = numero_laptop
           AND mc3.tipo_componente = tipo_de_componente
           AND (c.estado IS NULL OR c.estado <> 'EDC004');

        IF total_instalados + 1 > capacidad_permitida THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Capacidad_Componente: se excede la capacidad de ese tipo de componente para el modelo de la laptop';
        END IF;

    END IF;
END$$


-- Diferencias con el de arriba:
--   1. Sólo actúa cuando el vínculo con el ensamblaje CAMBIA y termina
--      apuntando a uno. Soltar la pieza (queda en NULL) o tocarle cualquier
--      otra columna no revalida nada; el <=> compara tolerando nulos.
--   2. El conteo excluye la propia pieza (c.numero <> NEW.numero). Sin eso,
--      mover un componente de un registro a otro DE LA MISMA laptop se contaría
--      a sí mismo y daría un falso "se excede la capacidad".

CREATE TRIGGER tg_Validar_Capacidad_Componente_Cambio
BEFORE UPDATE ON componente
FOR EACH ROW
BEGIN
    DECLARE numero_laptop        INT;
    DECLARE modelo_de_laptop VARCHAR(8);
    DECLARE tipo_de_componente          VARCHAR(8);
    DECLARE capacidad_permitida     INT;
    DECLARE total_instalados    INT;

    IF NOT (NEW.registro_ensamblaje <=> OLD.registro_ensamblaje)
       AND NEW.registro_ensamblaje IS NOT NULL
       AND NEW.modelo IS NOT NULL
    THEN

        SELECT re.laptop, l.modelo
          INTO numero_laptop, modelo_de_laptop
          FROM registro_ensamblaje re
          JOIN laptop l ON l.numero = re.laptop
         WHERE re.numero = NEW.registro_ensamblaje;

        SELECT mc.tipo_componente
          INTO tipo_de_componente
          FROM modelo_componente mc
         WHERE mc.codigo = NEW.modelo;

        SELECT MAX(mlc.capacidad)
          INTO capacidad_permitida
          FROM modelo_laptop_componente mlc
          JOIN modelo_componente mc2 ON mc2.codigo = mlc.modelo_componente
         WHERE mlc.modelo_laptop   = modelo_de_laptop
           AND mc2.tipo_componente = tipo_de_componente;

        IF capacidad_permitida IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Capacidad_Componente: el tipo de componente no es compatible con el modelo de la laptop';
        END IF;

        SELECT COUNT(*)
          INTO total_instalados
          FROM componente c
          JOIN registro_ensamblaje re2 ON re2.numero = c.registro_ensamblaje
          JOIN modelo_componente   mc3 ON mc3.codigo = c.modelo
         WHERE re2.laptop          = numero_laptop
           AND mc3.tipo_componente = tipo_de_componente
           AND c.numero            <> NEW.numero
           AND (c.estado IS NULL OR c.estado <> 'EDC004');

        IF total_instalados + 1 > capacidad_permitida THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Capacidad_Componente: Se excede la capacidad de ese tipo de componente para el modelo de la laptop';
        END IF;

    END IF;
END$$

-- ----------------------------------------------------------------------------
-- tg_Validar_Compatibilidad_Componente         BEFORE INSERT ON componente
-- tg_Validar_Compatibilidad_Componente_Cambio  BEFORE UPDATE ON componente
-- ----------------------------------------------------------------------------
-- Que una pieza no entre al stock de una línea que no la ensambla. La
-- compatibilidad no vive en la línea sino en sus estaciones
-- (estacion_compatibilidad_componente), así que basta con que UNA estación de
-- esa línea monte ese modelo.
--
-- No confundir con los dos de arriba: aquéllos miran el BOM del modelo de
-- laptop —cuántas piezas de un tipo caben en la máquina—, éste mira el catálogo
-- de la planta —qué piezas sabe montar la línea—. Una pieza puede pasar uno y
-- reprobar el otro.
--
-- Son dos comprobaciones, no una. La de que el modelo exista PARECE redundante
-- con FK_componente_modelo, y no lo es: InnoDB revisa las foráneas DESPUÉS de
-- los triggers BEFORE, así que sin ella un modelo inventado nunca llega al 1452
-- y sale por la segunda comprobación con 'ninguna estación lo ensambla', que es
-- verdad pero manda a buscar el problema al lado equivocado.
--
-- Lo que a propósito NO mira es estacion.activo: apagar una estación por
-- mantenimiento no debería volver ilegal el material que ya está pedido para
-- esa línea.
--
-- Consecuencia a tener presente: LIN005 es de tipo Embalaje y no tiene ninguna
-- fila en estacion_compatibilidad_componente, así que con esta regla ningún
-- componente puede quedarse en su inventario. Es lo correcto —ahí no se
-- ensambla, se empaca—, pero si algún día hace falta, se le dan
-- compatibilidades; no se quita el trigger.
--
--
-- La tercera comprobación no es de compatibilidad, es de estado de la orden;
-- vive aquí porque comparte evento, que es como este archivo agrupa las reglas.
-- Lee al revés de lo que uno esperaría, así que conviene decirlo claro:
-- `orden_material.recepcion` NO es "ya llegó el material, ahora sí captúralo";
-- es el sello de CERRADA que sp_Recibir_Orden_Material estampa al terminar de
-- dar de alta las piezas. En NULL la orden está abierta y admite componentes;
-- en cuanto tiene fecha, ya no.
--
-- Por eso el procedimiento no choca consigo mismo: inserta primero y sella
-- después, así que sus propias piezas entran con la orden todavía abierta. Lo
-- que se tapa es el otro camino, el del serializer de componente, que deja
-- escribir `orden_material` a mano (Servicios/api/serializers.py): sin esto se
-- le seguían colgando piezas a una orden cerrada y el conteo de recibido contra
-- pedido dejaba de cuadrar.
--
-- Que la orden exista no se comprueba: eso sí lo corta FK_componente_orden_material,
-- con un 1452 pelón, y sólo se alcanza mandando un número inventado por la API.
--
-- El gemelo BEFORE UPDATE va abajo. Sin él la regla se saltaba entera: mover
-- una pieza de línea —o reasignarle la orden— con un UPDATE no pasaba por aquí,
-- y ése no es un camino teórico, es ComponenteModifyAPIView
-- (Servicios/componentes/views.py) con un PATCH a /componentes/mod/<numero>/,
-- que expone `linea` y `modelo` como cualquier otro campo.

CREATE TRIGGER tg_Validar_Compatibilidad_Componente
BEFORE INSERT ON componente
FOR EACH ROW
BEGIN

    IF NEW.modelo IS NOT NULL
       AND NOT EXISTS (
               SELECT 1
                 FROM modelo_componente mc
                WHERE mc.codigo = NEW.modelo)
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Componente: ese modelo de componente no existe';
    END IF;

    -- Pieza suelta, sin orden que la respalde: no hay orden que revisar.
    IF NEW.orden_material IS NOT NULL
       AND EXISTS (
               SELECT 1
                 FROM orden_material om
                WHERE om.numero    = NEW.orden_material
                  AND om.recepcion IS NOT NULL)
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Componente: esa orden de material ya se recibió, no admite más piezas';
    END IF;

    -- Pieza sin línea o sin modelo todavía: no hay contra qué comparar.
    IF NEW.linea IS NOT NULL AND NEW.modelo IS NOT NULL THEN

        IF NOT EXISTS (
                SELECT 1
                  FROM estacion_compatibilidad_componente ecc
                  JOIN estacion e ON e.codigo = ecc.estacion
                 WHERE e.linea               = NEW.linea
                   AND ecc.modelo_componente = NEW.modelo)
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Componente: ninguna estación de esa línea ensambla ese modelo de componente';
        END IF;

    END IF;
END$$


-- Diferencias con el de arriba:
--   1. Cada comprobación se despierta sólo si CAMBIÓ lo que vigila: el modelo
--      para la primera, la orden para la segunda, la línea o el modelo para la
--      tercera. El <=> compara tolerando nulos. Tocarle el estado, la
--      descripción o el registro de ensamblaje no revalida nada, que es lo que
--      hacen sp_Cancelar_Orden_Produccion, sp_Cancelar_Laptop y el checklist a
--      cada rato; revalidar ahí sólo costaría consultas.
--   2. Por lo mismo NO regulariza lo que ya está guardado. Una pieza que hoy
--      viviera en una línea que no la ensambla se puede seguir editando por sus
--      otras columnas; lo que se cierra es que un UPDATE la MUEVA a una
--      combinación mala. Para lo viejo hace falta una limpieza de datos, no un
--      trigger.
--   3. La de la orden pide además que la orden CAMBIE. Que la pieza siga
--      colgada de la misma orden ya sellada no es motivo para bloquear el
--      UPDATE: es la vida normal de una pieza recibida.

CREATE TRIGGER tg_Validar_Compatibilidad_Componente_Cambio
BEFORE UPDATE ON componente
FOR EACH ROW
BEGIN

    IF NOT (NEW.modelo <=> OLD.modelo)
       AND NEW.modelo IS NOT NULL
       AND NOT EXISTS (
               SELECT 1
                 FROM modelo_componente mc
                WHERE mc.codigo = NEW.modelo)
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Componente_Cambio: ese modelo de componente no existe';
    END IF;

    IF NOT (NEW.orden_material <=> OLD.orden_material)
       AND NEW.orden_material IS NOT NULL
       AND EXISTS (
               SELECT 1
                 FROM orden_material om
                WHERE om.numero    = NEW.orden_material
                  AND om.recepcion IS NOT NULL)
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Componente_Cambio: esa orden ya se recibió, no admite más piezas';
    END IF;

    IF (NOT (NEW.linea <=> OLD.linea) OR NOT (NEW.modelo <=> OLD.modelo))
       AND NEW.linea  IS NOT NULL
       AND NEW.modelo IS NOT NULL
    THEN

        IF NOT EXISTS (
                SELECT 1
                  FROM estacion_compatibilidad_componente ecc
                  JOIN estacion e ON e.codigo = ecc.estacion
                 WHERE e.linea               = NEW.linea
                   AND ecc.modelo_componente = NEW.modelo)
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Componente_Cambio: ninguna estación de esa línea ensambla ese modelo';
        END IF;

    END IF;
END$$



-- ============================================================================
-- D E T A L L E   D E   M A T E R I A L
-- ============================================================================
--
-- La misma regla que los dos de arriba, un paso antes. Aquéllos vigilan la
-- RECEPCIÓN —qué pieza entra al stock de la línea—; éstos vigilan la SOLICITUD
-- —qué modelos se le pueden pedir a la orden—, que es donde se pidió que
-- estuviera: de la orden de material de una línea sólo se puede solicitar
-- material que esa línea ensamble.
--
-- Sin ellos la orden admitía cualquier modelo y el error salía hasta que
-- llegaba el camión, en el peor momento posible: sp_Recibir_Orden_Material se
-- frenaba a media captura, no daba de alta ni los renglones buenos, la orden se
-- quedaba sin sellar —recepcion en NULL, o sea abierta para siempre— y el
-- mensaje hablaba de un trigger sobre `componente` que el supervisor nunca
-- tocó. Aquí el renglón malo se rechaza solo, cuando se está armando la orden,
-- y los demás entran.
--
--   _Detalle_Material         BEFORE INSERT — se le agrega un material.
--   _Detalle_Material_Cambio  BEFORE UPDATE — se le cambia el modelo al material
--                             o se le mueve a otra orden. Cambiar sólo la
--                             cantidad no revalida la compatibilidad.
--
-- Los dos revisan además que la orden siga ABIERTA. `recepcion` en NULL es
-- abierta; en cuanto sp_Recibir_Orden_Material la sella —lo hace sólo cuando la
-- orden quedó completa— la orden ya no admite materiales nuevos ni cambios en
-- los que tiene. Sin esto se le podían seguir colgando materiales a una orden
-- ya recibida, que nadie iba a surtir nunca, o subirle la cantidad a los que ya
-- tenía y dejar el 'recibido completo' mintiendo. Es la misma regla que la
-- segunda comprobación de tg_Validar_Compatibilidad_Componente, del otro lado:
-- allá cierra el paso a las piezas, aquí a lo que se pide.
--
--   _Detalle_Material_Baja    BEFORE DELETE — se quita un material de la orden.
--                             Lo corta si de ese material ya llegaron piezas.
--
-- La compatibilidad se mira contra `orden_material.linea` y no contra la
-- estación: basta con que UNA estación de esa línea monte el modelo, igual que
-- en el de componente.
--
-- Órdenes sin línea: la columna admite NULL y la orden se puede guardar antes
-- de elegirla. Mientras no la tenga no hay contra qué comparar y los renglones
-- pasan; de todos modos sp_Recibir_Orden_Material no la deja recibir así. Ese
-- hueco se cierra con un NOT NULL en la columna, no con más lógica aquí.
--
-- Lo que a propósito NO cubren: cambiarle la línea a una orden que ya tiene
-- renglones (UPDATE sobre orden_material) puede dejarlos incompatibles a todos
-- de golpe. Eso es otra tabla y otro evento, y la decisión de qué hacer con los
-- renglones ya escritos —rechazar el cambio o borrarlos— no es obvia.
--
-- Que la orden exista no se comprueba: eso lo corta FK_detalle_material_orden.
-- Que el modelo exista sí, y por la misma razón que allá arriba: InnoDB revisa
-- las foráneas DESPUÉS de los BEFORE, así que sin esa comprobación un modelo
-- inventado nunca llega al 1452 y sale por 'esa línea no lo ensambla', que es
-- verdad pero manda a buscar el problema al lado equivocado.

CREATE TRIGGER tg_Validar_Compatibilidad_Detalle_Material
BEFORE INSERT ON detalle_material
FOR EACH ROW
BEGIN
    DECLARE linea_orden     VARCHAR(8) DEFAULT NULL;
    DECLARE recepcion_orden DATETIME   DEFAULT NULL;

    IF NOT EXISTS (
           SELECT 1
             FROM modelo_componente mc
            WHERE mc.codigo = NEW.modelo)
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Detalle_Material: ese modelo de componente no existe';
    END IF;

    -- Las dos cosas que hay que saber de la orden, en una sola consulta.
    SELECT om.linea, om.recepcion
      INTO linea_orden, recepcion_orden
      FROM orden_material om
     WHERE om.numero = NEW.orden;

    IF recepcion_orden IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Detalle_Material: esa orden ya se recibió, no admite más materiales';
    END IF;

    -- Orden todavía sin línea: no hay contra qué comparar.
    IF linea_orden IS NOT NULL
       AND NOT EXISTS (
               SELECT 1
                 FROM estacion_compatibilidad_componente ecc
                 JOIN estacion e ON e.codigo = ecc.estacion
                WHERE e.linea               = linea_orden
                  AND ecc.modelo_componente = NEW.modelo)
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Detalle_Material: esa línea no ensambla ese modelo de componente';
    END IF;
END$$


-- Diferencia con el de arriba: sólo se despierta si cambió el modelo o la
-- orden, que es lo único que puede volver malo un renglón que ya estaba bien.
-- Corregir la cantidad —el UPDATE de todos los días— no vuelve a consultar
-- nada.

CREATE TRIGGER tg_Validar_Compatibilidad_Detalle_Material_Cambio
BEFORE UPDATE ON detalle_material
FOR EACH ROW
BEGIN
    DECLARE linea_orden     VARCHAR(8) DEFAULT NULL;
    DECLARE recepcion_orden DATETIME   DEFAULT NULL;

    -- Una orden recibida está cerrada, y eso se mira en CUALQUIER update, no
    -- sólo cuando cambia el modelo: subirle la cantidad a un material de una
    -- orden ya sellada es pedir más material por la puerta de atrás, y deja el
    -- 'recibido completo' mintiendo. Se miran las dos órdenes, la de antes y la
    -- de después, para que tampoco se pueda sacar un material de una orden
    -- cerrada ni meterlo a otra.
    SELECT MAX(om.recepcion)
      INTO recepcion_orden
      FROM orden_material om
     WHERE om.numero IN (NEW.orden, OLD.orden);

    IF recepcion_orden IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Detalle_Material_Cambio: esa orden ya se recibió';
    END IF;

    IF NOT (NEW.modelo <=> OLD.modelo)
       OR NOT (NEW.orden  <=> OLD.orden)
    THEN

        IF NOT EXISTS (
               SELECT 1
                 FROM modelo_componente mc
                WHERE mc.codigo = NEW.modelo)
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Detalle_Material_Cambio: ese modelo no existe';
        END IF;

        SELECT om.linea
          INTO linea_orden
          FROM orden_material om
         WHERE om.numero = NEW.orden;

        IF linea_orden IS NOT NULL
           AND NOT EXISTS (
                   SELECT 1
                     FROM estacion_compatibilidad_componente ecc
                     JOIN estacion e ON e.codigo = ecc.estacion
                    WHERE e.linea               = linea_orden
                      AND ecc.modelo_componente = NEW.modelo)
        THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Detalle_Material_Cambio: esa línea no ensambla ese modelo';
        END IF;

    END IF;
END$$


-- El de baja no mira la fecha de recepción de la orden, mira las PIEZAS: si de
-- ese material con esa orden ya llegó aunque sea una, el renglón no se puede
-- quitar. Es a propósito más fino que 'la orden ya se recibió':
--
--   * Una orden puede tener piezas encima sin estar sellada todavía —recepción
--     parcial, o piezas capturadas a mano desde el formulario de componente—.
--     Ahí borrar el material también deja piezas huérfanas, y mirar sólo
--     `recepcion` lo dejaría pasar.
--   * Al revés, en una orden con varios materiales puede haber llegado uno y
--     otro no. El que no llegó sí se puede quitar; corregir una orden a la que
--     todavía no le surten un modelo es trabajo normal, no un error.
--
-- Lo que se evita es dejar componentes en el inventario apuntando a un renglón
-- que ya no existe: la orden diría que nunca pidió ese modelo y el almacén
-- tendría las piezas.
--
-- Para quitarlo de todos modos hay que dar de baja primero las piezas, que es
-- justo la decisión que alguien tiene que tomar a conciencia.

CREATE TRIGGER tg_Validar_Compatibilidad_Detalle_Material_Baja
BEFORE DELETE ON detalle_material
FOR EACH ROW
BEGIN

    IF EXISTS (
           SELECT 1
             FROM componente c
            WHERE c.orden_material = OLD.orden
              AND c.modelo         = OLD.modelo)
    THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error tg_Validar_Compatibilidad_Detalle_Material_Baja: ese material ya tiene piezas recibidas';
    END IF;

END$$


DELIMITER ;



-- ============================================================================
-- SINCRONIZACIÓN INICIAL
-- ============================================================================
-- Los triggers de arriba sólo actúan de aquí en adelante. Esto pone al día lo
-- que ya está capturado, para que cant_producida y cant_rechazada arranquen
-- cuadradas con las laptops reales de cada orden.
--
-- Las dos se siembran con un COUNT aunque después se lleven sumando: sobre lo
-- que ya estaba capturado no hay delta que aplicar, no pasó por ningún trigger.
-- Este UPDATE es el punto de partida de las dos fórmulas, y también la forma de
-- recuadrarlas si algún día alguien mueve las laptops por fuera.

UPDATE orden_produccion op
   SET op.cant_producida = (
           SELECT COUNT(*)
             FROM laptop l
            WHERE l.orden  = op.folio
              AND l.estado IN ('APROV', 'EMBALA')
       ),
       op.cant_rechazada = (
           SELECT COUNT(*)
             FROM laptop l
            WHERE l.orden  = op.folio
              AND l.estado = 'RECHA'
       );



-- ============================================================================
-- LAS CADENAS QUE SE ENCADENAN
-- ============================================================================
--
-- Un INSERT en laptop:
--
--   tg_Arrancar_Laptop_En_Ensamblaje   REGIS -> PENSAM
--   tg_Laptop_Alta                     arranca la orden, le suma su delta y
--                                      abre el ensamblaje de la primera línea
--     └─ ese INSERT dispara tg_Validar_Apertura_Ensamblaje
--
-- Un INSERT en inspeccion_calidad con resultado = 1 en la última línea:
--
--   tg_Actualizar_Estado_Laptop_Inspeccion_Calidad   cierra y marca APROV
--     ├─ tg_Generar_Numero_Serie_Final   (BEFORE UPDATE laptop) pone la serie
--     └─ tg_Laptop_Cambio                (AFTER UPDATE laptop) le suma 1 a
--                                        cant_producida
--
-- Un INSERT en inspeccion_calidad con resultado = 0:
--
--   tg_Actualizar_Estado_Laptop_Inspeccion_Calidad   cierra y marca RECHA
--     └─ tg_Laptop_Cambio                (AFTER UPDATE laptop) le suma 1 a
--                                        cant_rechazada. Es la vía por la que
--                                        se mueve el contador casi siempre.--
-- Y en una línea intermedia, ese mismo INSERT abre el registro de la siguiente,
-- que vuelve a pasar por tg_Validar_Apertura_Ensamblaje.
--
-- Un INSERT en registro_embalaje:
--
--   tg_Registrar_Embalaje              laptop -> EMBALA, y la orden -> COMP si
--                                      ya se embalaron todas
--     ├─ tg_Generar_Numero_Serie_Final  no actúa: no es transición a APROV
--     └─ tg_Laptop_Cambio               delta 0 (la laptop ya contaba desde
--                                       APROV: los dos términos valen 1)
--
-- OJO: los UPDATE de laptop de esas cadenas pasan por tg_Laptop_Cambio, pero
-- ahí NO cambia la columna `orden`, así que su rama de arranque no se cumple.



-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

SELECT trigger_name,
       event_manipulation AS evento,
       event_object_table AS tabla,
       action_timing      AS momento
  FROM information_schema.triggers
 WHERE trigger_schema = 'cuatro'
 ORDER BY event_object_table, action_timing, action_order;
