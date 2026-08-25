from django.db import models
from lineas.models import Estacion, Linea
# Create your models here.

 
''' AQUI ESTAN LOS MODELS DE:
│    TipoComp
│    EdoComponente
│    LoteComp
│    ModeloComponente
│    ModeloLaptopComponente  (tabla puente M a M: qué componentes lleva un modelo de laptop)
│    EstacionCompatibilidadComponente  (tabla puente M a M: qué componentes sabe montar una estación)
│    OrdenMaterial
│    DetalleMaterial
│    Componente
│    VistaComponente  (mapea la vista SQL vista_componentes, ver DB/vistas.sql)
'''
# Create your models here.
 
 
# TIPOCOMP — catálogo de tipos de componente (Procesador, RAM, SSD, etc.)
class TipoComp(models.Model):
    codigo = models.CharField(primary_key=True, max_length=8)
    nombre = models.CharField(unique=True, max_length=32, blank=True, null=True)
    # Qué tipo tiene que estar montado ANTES que éste: el procesador necesita la
    # tarjeta madre, la cámara necesita la pantalla. NULL = no depende de nada
    # (el chasis inferior, que es por donde se empieza).
    necesario = models.ForeignKey('self', models.DO_NOTHING, db_column='necesario',
                                  blank=True, null=True, related_name='habilita')

    class Meta:
        managed = False
        db_table = 'tipo_comp'
 
 
# EDOCOMPONENTE — catálogo de estados del componente (Disponible, En Uso, Dañado, Mermado)
class EdoComponente(models.Model):
    codigo = models.CharField(primary_key=True, max_length=8)
    nombre = models.CharField(unique=True, max_length=32, blank=True, null=True)
    descripcion = models.CharField(max_length=64, blank=True, null=True)
 
    class Meta:
        managed = False
        db_table = 'edo_componente'
 
 
# LOTECOMP — catálogo de lotes de componentes
class LoteComp(models.Model):
    codigo = models.CharField(primary_key=True, max_length=12)
    descripcion = models.CharField(max_length=64, blank=True, null=True)
 
    class Meta:
        managed = False
        db_table = 'lote_comp'
 
 
# MODELOCOMPONENTE
class ModeloComponente(models.Model):
    codigo = models.CharField(primary_key=True, max_length=8)
    nombre = models.CharField(max_length=256, blank=True, null=True)
    tipo_componente = models.ForeignKey(TipoComp, models.DO_NOTHING, db_column='tipo_componente', blank=True, null=True)
    fabricante = models.CharField(max_length=64, blank=True, null=True)
 
    class Meta:
        managed = False
        db_table = 'modelo_componente'


# MODELOLAPTOPCOMPONENTE
class ModeloLaptopComponente(models.Model):
    pk = models.CompositePrimaryKey('modelo_laptop', 'modelo_componente')
    modelo_laptop = models.ForeignKey('produccion.ModeloLaptop', models.DO_NOTHING, db_column='modelo_laptop')
    modelo_componente = models.ForeignKey(ModeloComponente, models.DO_NOTHING, db_column='modelo_componente')
    capacidad = models.IntegerField(blank=True, null=True, default=1)

    class Meta:
        managed = False
        db_table = 'modelo_laptop_componente'


# ESTACIONCOMPATIBILIDADCOMPONENTE — qué modelos de componente sabe montar cada
# estación. Es el catálogo con el que los triggers de DB/triggers.sql deciden si
# una línea puede pedir un material: basta con que UNA de sus estaciones lo
# ensamble.
#
# No confundir con ModeloLaptopComponente, que es el BOM —qué piezas lleva una
# laptop—. Ésta es la capacidad de la planta: qué sabe armar cada estación. Una
# pieza puede estar en el BOM de un modelo y aun así no tocarle a una línea.
class EstacionCompatibilidadComponente(models.Model):
    numero = models.AutoField(primary_key=True)
    estacion = models.ForeignKey(Estacion, models.DO_NOTHING, db_column='estacion')
    modelo_componente = models.ForeignKey(ModeloComponente, models.DO_NOTHING, db_column='modelo_componente')

    class Meta:
        managed = False
        db_table = 'estacion_compatibilidad_componente'


# ORDENMATERIAL
class OrdenMaterial(models.Model):
    # Las tres fechas son DATETIME en la base y cada una la escribe alguien
    # distinto:
    #   solicitud   la pone el sistema al crear la orden (no se captura)
    #   necesitada  la captura quien pide el material: para cuándo lo requiere
    #   recepcion   la sella sp_Recibir_Orden_Material cuando la orden queda
    #               completa; en NULL la orden sigue abierta
    numero = models.AutoField(primary_key=True)
    solicitud = models.DateTimeField(blank=True, null=True)
    necesitada = models.DateTimeField(blank=True, null=True)
    recepcion = models.DateTimeField(blank=True, null=True)
    linea = models.ForeignKey(Linea, models.DO_NOTHING, db_column='linea', blank=True, null=True)
 
    class Meta:
        managed = False
        db_table = 'orden_material'
 
 
# DETALLEMATERIAL — detalle (línea de pedido) de una orden de material.
# La tabla tiene PRIMARY KEY (orden, modelo) y NO tiene columna id, falto declararla compuesta
class DetalleMaterial(models.Model):
    pk = models.CompositePrimaryKey('orden', 'modelo')
    orden = models.ForeignKey(OrdenMaterial, models.DO_NOTHING, db_column='orden')
    modelo = models.ForeignKey(ModeloComponente, models.DO_NOTHING, db_column='modelo')
    cantidad = models.IntegerField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'detalle_material'
 
 
# COMPONENTE
class Componente(models.Model):
    numero = models.AutoField(primary_key=True)
    num_serie = models.CharField(max_length=18, blank=True, null=True)
    descripcion = models.CharField(max_length=256, blank=True, null=True)
    linea = models.ForeignKey(Linea, models.DO_NOTHING, db_column='linea', blank=True, null=True)
    orden_material = models.ForeignKey(OrdenMaterial, models.DO_NOTHING, db_column='orden_material', blank=True, null=True)
 
    # NOTA: registro_ensamblaje pertenecea produccion pero ese
    # modelo (RegistroEnsamblaje) aún no existe ahí. Se deja como IntegerField
    # simple -- la integridad ya la garantiza la FK real en MySQL (estructura.sql).
    # Cuando exista produccion.models.RegistroEnsamblaje, subir esto a ForeignKey.
    registro_ensamblaje = models.IntegerField(blank=True, null=True)
 
    modelo = models.ForeignKey(ModeloComponente, models.DO_NOTHING, db_column='modelo', blank=True, null=True)
    lote = models.ForeignKey(LoteComp, models.DO_NOTHING, db_column='lote', blank=True, null=True)
    estado = models.ForeignKey(EdoComponente, models.DO_NOTHING, db_column='estado', blank=True, null=True)
 
    class Meta:
        managed = False
        db_table = 'componente'
 
 
# VISTACOMPONENTE — consulta general del módulo (vista_componentes en DB/vistas.sql)
class VistaComponente(models.Model):
    numero = models.IntegerField(primary_key=True)
    num_serie = models.CharField(max_length=18, blank=True, null=True)
    descripcion = models.CharField(max_length=256, blank=True, null=True)
    linea_codigo = models.CharField(max_length=8, blank=True, null=True)
    linea_nombre = models.CharField(max_length=32, blank=True, null=True)
    orden_material = models.IntegerField(blank=True, null=True)
    registro_ensamblaje = models.IntegerField(blank=True, null=True)
    modelo_codigo = models.CharField(max_length=8, blank=True, null=True)
    modelo_nombre = models.CharField(max_length=256, blank=True, null=True)
    modelo_fabricante = models.CharField(max_length=64, blank=True, null=True)
    lote_codigo = models.CharField(max_length=12, blank=True, null=True)
    estado_codigo = models.CharField(max_length=8, blank=True, null=True)
    estado_nombre = models.CharField(max_length=32, blank=True, null=True)
 
    class Meta:
        managed = False
        db_table = 'vista_componentes'
