-- Active: 1783038914702@@localhost@3306@cuatro

-- TRACEX — Estructura de base de datos
-- Version: 2026-07-15

DROP DATABASE IF EXISTS cuatro;
CREATE DATABASE IF NOT EXISTS cuatro CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE cuatro;

SET NAMES utf8mb4;
USE cuatro;

-- -------------------------------------mysql-------------------
-- ESTRUCTURA DE TABLAS
-- --------------------------------------------------------

DROP TABLE IF EXISTS componente;
CREATE TABLE componente (
  numero int NOT NULL AUTO_INCREMENT,
  num_serie varchar(18) DEFAULT NULL,
  descripcion varchar(256) DEFAULT NULL,
  linea varchar(8) DEFAULT NULL,
  orden_material int DEFAULT NULL,
  registro_ensamblaje int DEFAULT NULL,
  modelo varchar(8) DEFAULT NULL,
  lote varchar(12) DEFAULT NULL,
  estado varchar(8) DEFAULT NULL,
  PRIMARY KEY (numero)
);

-- Qué piezas concretas reprobó una inspección. La inspección dice si la laptop
-- pasa o no; esto dice POR CUÁL componente, que es lo que sirve para reclamar al
-- proveedor o detectar un lote malo. Sin esta tabla el motivo solo vivía en el
-- texto libre de `observaciones` y no se podía cruzar con nada.
DROP TABLE IF EXISTS detalle_inspeccion;
CREATE TABLE detalle_inspeccion (
  inspeccion int NOT NULL,
  componente int NOT NULL,
  observacion varchar(256) DEFAULT NULL,
  PRIMARY KEY (inspeccion, componente)
);

DROP TABLE IF EXISTS detalle_material;
CREATE TABLE detalle_material (
  orden int NOT NULL,
  modelo varchar(8) NOT NULL,
  cantidad int DEFAULT NULL,
  PRIMARY KEY (orden, modelo)
);

DROP TABLE IF EXISTS edo_componente;
CREATE TABLE edo_componente (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  descripcion varchar(64) DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS edo_laptop;
CREATE TABLE edo_laptop (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS edo_linea;
CREATE TABLE edo_linea (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  descripcion varchar(64) DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS edo_produccion;
CREATE TABLE edo_produccion (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS empleado;
CREATE TABLE empleado (
  numero int NOT NULL AUTO_INCREMENT,
  nombrePila varchar(50) DEFAULT NULL,
  primerApell varchar(32) DEFAULT NULL,
  segundoApell varchar(32) DEFAULT NULL,
  rol varchar(8) DEFAULT NULL,
  turno varchar(8) DEFAULT NULL,
  activo BOOLEAN DEFAULT FALSE,
  PRIMARY KEY (numero)
);

DROP TABLE IF EXISTS empleado_estacion;
CREATE TABLE empleado_estacion (
  empleado int NOT NULL,
  estacion varchar(8) NOT NULL,
  fecha_inicio date NOT NULL,
  fecha_fin date NULL,
  PRIMARY KEY (empleado, estacion, fecha_inicio)
);

DROP TABLE IF EXISTS empleado_linea;
CREATE TABLE empleado_linea (
  empleado int NOT NULL,
  linea varchar(8) NOT NULL,
  fecha_inicio date NOT NULL,
  fecha_fin date NULL,
  PRIMARY KEY (empleado, linea, fecha_inicio)
);

DROP TABLE IF EXISTS estacion;
CREATE TABLE estacion (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  descripcion varchar(128) DEFAULT NULL,
  linea varchar(8) DEFAULT NULL,
  activo BOOLEAN DEFAULT FALSE,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS inspeccion_calidad;
CREATE TABLE inspeccion_calidad (
  numero int NOT NULL AUTO_INCREMENT,
  resultado tinyint(1) DEFAULT NULL,
  observaciones varchar(256) DEFAULT NULL,
  fecha date DEFAULT NULL,
  hora time DEFAULT NULL,
  laptop int DEFAULT NULL,
  empleado int DEFAULT NULL,
  linea varchar(8) DEFAULT NULL,
  PRIMARY KEY (numero)
);

DROP TABLE IF EXISTS laptop;
CREATE TABLE laptop (
  numero int NOT NULL AUTO_INCREMENT,
  num_serie VARCHAR(50) NOT NULL,
  orden int DEFAULT NULL,
  modelo varchar(8) DEFAULT NULL,
  estado varchar(8) DEFAULT NULL,
  lote varchar(8) DEFAULT NULL,
  PRIMARY KEY (numero)
);

DROP TABLE IF EXISTS linea;
CREATE TABLE linea (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  descripcion varchar(128) DEFAULT NULL,
  tipo varchar(8) DEFAULT NULL,
  estado varchar(8) DEFAULT NULL,
  activo BOOLEAN DEFAULT TRUE,
  siguiente VARCHAR(8) DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS lote_comp;
CREATE TABLE lote_comp (
  codigo varchar(12) NOT NULL,
  descripcion varchar(64) DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS lote_laptop;
CREATE TABLE lote_laptop (
  codigo varchar(8) NOT NULL,
  fecha date DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS modelo_componente;
CREATE TABLE modelo_componente (
  codigo varchar(8) NOT NULL,
  nombre varchar(256) DEFAULT NULL,
  tipo_componente varchar(8) DEFAULT NULL,
  fabricante VARCHAR(64) NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS modelo_laptop;
CREATE TABLE modelo_laptop (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS modelo_laptop_componente;
CREATE TABLE modelo_laptop_componente (
  modelo_laptop varchar(8) NOT NULL,
  modelo_componente varchar(8) NOT NULL,
  capacidad int DEFAULT 1,
  PRIMARY KEY (modelo_laptop, modelo_componente)
);

DROP TABLE IF EXISTS orden_material;
CREATE TABLE orden_material (
  numero int NOT NULL AUTO_INCREMENT,
  solicitud   DATETIME DEFAULT NULL,
  necesitada  DATETIME DEFAULT NULL,
  recepcion   DATETIME DEFAULT NULL,
  linea varchar(8) DEFAULT NULL,
  PRIMARY KEY (numero)
);

DROP TABLE IF EXISTS orden_produccion;
CREATE TABLE orden_produccion (
  folio int NOT NULL AUTO_INCREMENT,
  fecha date DEFAULT NULL,
  hora time DEFAULT NULL,
  modelo_laptop varchar(8) DEFAULT NULL,
  cant_planificada INT DEFAULT 0,
  cant_producida int DEFAULT 0,
  cant_rechazada int DEFAULT 0,
  estado varchar(8) DEFAULT NULL,
  lote varchar(8) DEFAULT NULL,
  PRIMARY KEY (folio)
);

DROP TABLE IF EXISTS paro;
CREATE TABLE paro (
  numero int NOT NULL AUTO_INCREMENT,
  razon varchar(256) DEFAULT NULL,
  fecha_inicio date DEFAULT NULL,
  fecha_fin date DEFAULT NULL,
  hora_inicio time DEFAULT NULL,
  hora_fin time DEFAULT NULL,
  linea varchar(8) DEFAULT NULL,
  PRIMARY KEY (numero)
);

DROP TABLE IF EXISTS registro_embalaje;
CREATE TABLE registro_embalaje (
  numero int NOT NULL AUTO_INCREMENT,
  fecha date DEFAULT NULL,
  hora time DEFAULT NULL,
  laptop int DEFAULT NULL,
  tipo varchar(8) DEFAULT NULL,
  PRIMARY KEY (numero)
);

DROP TABLE IF EXISTS registro_ensamblaje;
CREATE TABLE registro_ensamblaje (
  numero int NOT NULL AUTO_INCREMENT,
  fecha_inicio date DEFAULT NULL,
  fecha_fin date DEFAULT NULL,
  hora_inicio time DEFAULT NULL,
  hora_fin time DEFAULT NULL,
  laptop int DEFAULT NULL,
  linea varchar(8) DEFAULT NULL,
  PRIMARY KEY (numero)
);

DROP TABLE IF EXISTS rol;
CREATE TABLE rol (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  descripcion varchar(130) DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS tipo_comp;
CREATE TABLE tipo_comp (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  necesario VARCHAR(8) DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS tipo_embalaje;
CREATE TABLE tipo_embalaje (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  PRIMARY KEY (codigo)
);

-- Qué proceso corre la línea (ensamblaje o embalaje). Es distinto de edo_linea:
-- ese dice cómo está la línea (activa, en paro...), este dice para qué sirve, y
-- es lo que decide si en ella se puede registrar ensamblaje.
DROP TABLE IF EXISTS tipo_linea;
CREATE TABLE tipo_linea (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  descripcion varchar(64) DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS turno;
CREATE TABLE turno (
  codigo varchar(8) NOT NULL,
  nombre varchar(32) DEFAULT NULL,
  hora_entrada time DEFAULT NULL,
  hora_salida time DEFAULT NULL,
  PRIMARY KEY (codigo)
);

DROP TABLE IF EXISTS usuario;
CREATE TABLE usuario (
  numero int NOT NULL AUTO_INCREMENT,
  usuario varchar(32) DEFAULT NULL,
  contrasena varchar(256) DEFAULT NULL,
  estado tinyint(1) DEFAULT NULL,
  empleado int DEFAULT NULL,
  PRIMARY KEY (numero)
);

DROP TABLE IF EXISTS estacion_compatibilidad_componente;
CREATE TABLE estacion_compatibilidad_componente(
  numero int NOT NULL AUTO_INCREMENT,
  estacion varchar(8) NOT NULL,
  modelo_componente varchar(8) NOT NULL,
  PRIMARY KEY (numero)
);

DROP TABLE IF EXISTS sesion;
#####ESTO ES PARA LOS TOKENS
CREATE TABLE sesion (
    id INT NOT NULL AUTO_INCREMENT,
    usuario INT NOT NULL,
    token CHAR(64) NOT NULL,
    fecha_inicio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_expiracion DATETIME NOT NULL,

    PRIMARY KEY (id),
    UNIQUE (token),

    CONSTRAINT fk_sesion_usuario
        FOREIGN KEY (usuario)
        REFERENCES usuario(numero)
        ON DELETE CASCADE
);

-- --------------------------------------------------------
-- LLAVES FORÁNEAS
-- --------------------------------------------------------

-- Llaves foráneas para la tabla componente
ALTER TABLE componente ADD CONSTRAINT FK_componente_linea FOREIGN KEY (linea) REFERENCES linea(codigo);
ALTER TABLE componente ADD CONSTRAINT FK_componente_orden_material FOREIGN KEY (orden_material) REFERENCES orden_material(numero);
ALTER TABLE componente ADD CONSTRAINT FK_componente_registro_ensamblaje FOREIGN KEY (registro_ensamblaje) REFERENCES registro_ensamblaje(numero);
ALTER TABLE componente ADD CONSTRAINT FK_componente_modelo FOREIGN KEY (modelo) REFERENCES modelo_componente(codigo);
ALTER TABLE componente ADD CONSTRAINT FK_componente_lote FOREIGN KEY (lote) REFERENCES lote_comp(codigo);
ALTER TABLE componente ADD CONSTRAINT FK_componente_estado FOREIGN KEY (estado) REFERENCES edo_componente(codigo);

-- Llaves foráneas para la tabla detalle_material
ALTER TABLE detalle_inspeccion ADD CONSTRAINT FK_detalle_inspeccion_inspeccion FOREIGN KEY (inspeccion) REFERENCES inspeccion_calidad(numero);
ALTER TABLE detalle_inspeccion ADD CONSTRAINT FK_detalle_inspeccion_componente FOREIGN KEY (componente) REFERENCES componente(numero);
ALTER TABLE detalle_material ADD CONSTRAINT FK_detalle_material_orden FOREIGN KEY (orden) REFERENCES orden_material(numero);
ALTER TABLE detalle_material ADD CONSTRAINT FK_detalle_material_modelo FOREIGN KEY (modelo) REFERENCES modelo_componente(codigo);

-- Llaves foráneas para la tabla empleado
ALTER TABLE empleado ADD CONSTRAINT FK_empleado_rol FOREIGN KEY (rol) REFERENCES rol(codigo);
ALTER TABLE empleado ADD CONSTRAINT FK_empleado_turno FOREIGN KEY (turno) REFERENCES turno(codigo);

-- Llaves foráneas para la tabla empleado_estacion
ALTER TABLE empleado_estacion ADD CONSTRAINT FK_empleado_estacion_empleado FOREIGN KEY (empleado) REFERENCES empleado(numero);
ALTER TABLE empleado_estacion ADD CONSTRAINT FK_empleado_estacion_estacion FOREIGN KEY (estacion) REFERENCES estacion(codigo);

-- Llaves foráneas para la tabla empleado_linea
ALTER TABLE empleado_linea ADD CONSTRAINT FK_empleado_linea_empleado FOREIGN KEY (empleado) REFERENCES empleado(numero);
ALTER TABLE empleado_linea ADD CONSTRAINT FK_empleado_linea_linea FOREIGN KEY (linea) REFERENCES linea(codigo);

-- Llaves foráneas para la tabla estacion
ALTER TABLE estacion ADD CONSTRAINT FK_estacion_linea FOREIGN KEY (linea) REFERENCES linea(codigo);

-- Llaves foráneas para la tabla inspeccion_calidad
ALTER TABLE inspeccion_calidad ADD CONSTRAINT FK_inspeccion_calidad_laptop FOREIGN KEY (laptop) REFERENCES laptop(numero);
ALTER TABLE inspeccion_calidad ADD CONSTRAINT FK_inspeccion_calidad_empleado FOREIGN KEY (empleado) REFERENCES empleado(numero);
ALTER TABLE inspeccion_calidad ADD CONSTRAINT FK_inspeccion_calidad_linea FOREIGN KEY (linea) REFERENCES linea(codigo);

-- Llaves foráneas para la tabla laptop
ALTER TABLE laptop ADD CONSTRAINT FK_laptop_orden FOREIGN KEY (orden) REFERENCES orden_produccion(folio);
ALTER TABLE laptop ADD CONSTRAINT FK_laptop_modelo FOREIGN KEY (modelo) REFERENCES modelo_laptop(codigo);
ALTER TABLE laptop ADD CONSTRAINT FK_laptop_estado FOREIGN KEY (estado) REFERENCES edo_laptop(codigo);
ALTER TABLE laptop ADD CONSTRAINT FK_laptop_lote FOREIGN KEY (lote) REFERENCES lote_laptop(codigo);

-- Llaves foráneas para la tabla linea
ALTER TABLE linea ADD CONSTRAINT FK_linea_estado FOREIGN KEY (estado) REFERENCES edo_linea(codigo);
ALTER TABLE linea ADD CONSTRAINT FK_linea_tipo FOREIGN KEY (tipo) REFERENCES tipo_linea(codigo);
ALTER TABLE linea ADD CONSTRAINT FK_linea_siguiente FOREIGN KEY (siguiente) REFERENCES linea(codigo);


-- Llaves foráneas para la tabla modelo_componente
ALTER TABLE modelo_componente ADD CONSTRAINT FK_modelo_componente_tipo_componente FOREIGN KEY (tipo_componente) REFERENCES tipo_comp(codigo);

-- Llves foraneas para la tabla tipo_comp
ALTER TABLE tipo_comp ADD CONSTRAINT FK_tipo_comp_necesario_instalado FOREIGN KEY (necesario) REFERENCES tipo_comp(codigo);

-- Llaves foráneas para la tabla puente modelo_laptop_componente
ALTER TABLE modelo_laptop_componente ADD CONSTRAINT FK_mlc_modelo_laptop FOREIGN KEY (modelo_laptop) REFERENCES modelo_laptop(codigo);
ALTER TABLE modelo_laptop_componente ADD CONSTRAINT FK_mlc_modelo_componente FOREIGN KEY (modelo_componente) REFERENCES modelo_componente(codigo);

-- Llaves foráneas para la tabla orden_material
ALTER TABLE orden_material ADD CONSTRAINT FK_orden_material_linea FOREIGN KEY (linea) REFERENCES linea(codigo);

-- Llaves foráneas para la tabla orden_produccion
ALTER TABLE orden_produccion ADD CONSTRAINT FK_orden_produccion_modelo_laptop FOREIGN KEY (modelo_laptop) REFERENCES modelo_laptop(codigo);
ALTER TABLE orden_produccion ADD CONSTRAINT FK_orden_produccion_estado FOREIGN KEY (estado) REFERENCES edo_produccion(codigo);
ALTER TABLE orden_produccion ADD CONSTRAINT FK_orden_produccion_lote FOREIGN KEY (lote) REFERENCES lote_laptop(codigo);

-- Llaves foráneas para la tabla paro
ALTER TABLE paro ADD CONSTRAINT FK_paro_linea FOREIGN KEY (linea) REFERENCES linea(codigo);

-- Llaves foráneas para la tabla registro_embalaje
ALTER TABLE registro_embalaje ADD CONSTRAINT FK_registro_embalaje_laptop FOREIGN KEY (laptop) REFERENCES laptop(numero);
ALTER TABLE registro_embalaje ADD CONSTRAINT FK_registro_embalaje_tipo FOREIGN KEY (tipo) REFERENCES tipo_embalaje(codigo);

-- Llaves foráneas para la tabla registro_ensamblaje (Agregadas)
ALTER TABLE registro_ensamblaje ADD CONSTRAINT FK_registro_ensamblaje_laptop FOREIGN KEY (laptop) REFERENCES laptop(numero);
ALTER TABLE registro_ensamblaje ADD CONSTRAINT FK_registro_ensamblaje_linea FOREIGN KEY (linea) REFERENCES linea(codigo);

-- Llaves foráneas para la tabla usuario (Agregadas)
ALTER TABLE usuario ADD CONSTRAINT FK_usuario_empleado FOREIGN KEY (empleado) REFERENCES empleado(numero);

-- Llaves foráneas para la tabla estacion_compatibilidad_componente
ALTER TABLE estacion_compatibilidad_componente ADD CONSTRAINT FK_estacion_compatibilidad_componente_estacion FOREIGN KEY (estacion) REFERENCES estacion(codigo);
ALTER TABLE estacion_compatibilidad_componente ADD CONSTRAINT FK_estacion_compatibilidad_componente_modelo_componente FOREIGN KEY (modelo_componente) REFERENCES modelo_componente(codigo);

-- --------------------------------------------------------
-- ÍNDICES ÚNICOS (RESTRICCIONES UNIQUE)
-- --------------------------------------------------------

CREATE UNIQUE INDEX IUK_edo_componente_nombre ON edo_componente(nombre);
CREATE UNIQUE INDEX IUK_edo_laptop_nombre ON edo_laptop(nombre);
CREATE UNIQUE INDEX IUK_edo_linea_nombre ON edo_linea(nombre);
CREATE UNIQUE INDEX IUK_edo_produccion_nombre ON edo_produccion(nombre);
CREATE UNIQUE INDEX IUK_linea_nombre ON linea(nombre);
CREATE UNIQUE INDEX IUK_modelo_laptop_nombre ON modelo_laptop(nombre);
CREATE UNIQUE INDEX IUK_rol_nombre ON rol(nombre);
CREATE UNIQUE INDEX IUK_tipo_comp_nombre ON tipo_comp(nombre);
CREATE UNIQUE INDEX IUK_tipo_embalaje_nombre ON tipo_embalaje(nombre);
CREATE UNIQUE INDEX IUK_tipo_linea_nombre ON tipo_linea(nombre);
CREATE UNIQUE INDEX IUK_turno_nombre ON turno(nombre);
CREATE UNIQUE INDEX IUK_usuario_usuario ON usuario(usuario);
CREATE UNIQUE INDEX IUK_usuario_empleado ON usuario(empleado);

CREATE UNIQUE INDEX IUK_serie_laptop ON laptop(num_serie);

CREATE UNIQUE INDEX IUK_estacion_compatibilidad_componente
    ON estacion_compatibilidad_componente(estacion, modelo_componente);

# Editar la PK de los empleados

#Modificar el default de los usuarios al registrarlos
ALTER TABLE usuario
MODIFY estado TINYINT(1) NOT NULL DEFAULT 1;


