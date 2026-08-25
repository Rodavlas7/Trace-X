
from django.utils import timezone

from rest_framework import serializers
from rest_framework.validators import UniqueTogetherValidator

from .models import *


# Catálogos

class TipoCompSerializer(serializers.ModelSerializer):
    class Meta:
        model = TipoComp
        fields = '__all__'


class EdoComponenteSerializer(serializers.ModelSerializer):
    class Meta:
        model = EdoComponente
        fields = '__all__'


class LoteCompSerializer(serializers.ModelSerializer):
    class Meta:
        model = LoteComp
        fields = '__all__'


class ModeloComponenteSerializer(serializers.ModelSerializer):
    class Meta:
        model = ModeloComponente
        fields = '__all__'


# ==================================================
# S E R I A L I Z E R S   D E   E D I C I O N
# ==================================================
#
# En estos catálogos la llave primaria es el 'codigo', no un id automático, así
# que DRF lo genera como campo obligatorio. En un PUT eso pide que el codigo
# venga en el cuerpo... pero el codigo ya viene en la URL y editarlo no tiene
# sentido: sería otro registro. El formulario del cliente lo muestra de solo
# lectura y no lo manda, y sin esto la edición se caía en 400
# ("codigo: This field is required").
#
# Se marca de solo lectura al editar: el que manda es el de la URL.


class LoteCompUpdateSerializer(LoteCompSerializer):
    class Meta(LoteCompSerializer.Meta):
        read_only_fields = ['codigo']


class ModeloComponenteUpdateSerializer(ModeloComponenteSerializer):
    class Meta(ModeloComponenteSerializer.Meta):
        read_only_fields = ['codigo']


# Tabla puente modelo_laptop <-> modelo_componente

class ModeloLaptopComponenteSerializer(serializers.ModelSerializer):
    """Para crear/editar renglones de la lista de materiales (BOM)."""
    class Meta:
        model = ModeloLaptopComponente
        # se listan explícitos para no exponer el campo virtual 'pk'
        fields = ['modelo_laptop', 'modelo_componente', 'capacidad']


class ModeloLaptopComponenteDetalleSerializer(serializers.ModelSerializer):
    """Solo lectura: el componente con su nombre/tipo y la capacidad,
    para anidarlo en el detalle de un modelo de laptop."""
    componente_codigo = serializers.CharField(source='modelo_componente.codigo', read_only=True)
    componente_nombre = serializers.CharField(source='modelo_componente.nombre', read_only=True)
    componente_tipo = serializers.CharField(source='modelo_componente.tipo_componente_id', read_only=True)
    componente_tipo_nombre = serializers.CharField(source='modelo_componente.tipo_componente.nombre', read_only=True)

    class Meta:
        model = ModeloLaptopComponente
        fields = ['componente_codigo', 'componente_nombre', 'componente_tipo',
                  'componente_tipo_nombre', 'capacidad']
 
 
# Ordenes de material
 
class OrdenMaterialSerializer(serializers.ModelSerializer):
    """Orden de material. De sus tres fechas el usuario sólo captura una.

    `solicitud` la sella create() con la hora del servidor: es cuándo se pidió
    el material, no un dato que nadie deba teclear ni corregir. `recepcion` la
    escribe sp_Recibir_Orden_Material cuando la orden queda completa. Las dos
    van de solo lectura para que la pantalla las muestre sin poder alterarlas;
    la única que se captura es `necesitada`.
    """

    class Meta:
        model = OrdenMaterial
        fields = '__all__'
        read_only_fields = ['solicitud', 'recepcion']

    def validate_necesitada(self, valor):
        """No se puede necesitar material en un momento que ya pasó."""

        if valor is None:
            return valor

        # Al editar sólo se revisa si de verdad cambió. Una orden de la semana
        # pasada tiene su fecha en el pasado por definición, y volver a guardarla
        # sin tocarle ese campo —para corregirle la línea, por ejemplo— no es un
        # error que haya que rechazar.
        if self.instance is not None and self.instance.necesitada == valor:
            return valor

        if valor < timezone.now():
            raise serializers.ValidationError(
                'La fecha y hora en que se necesita el material no puede ser anterior a este momento.'
            )

        return valor

    def create(self, validated_data):
        validated_data['solicitud'] = timezone.now()
        return super().create(validated_data)
 
 
class DetalleMaterialSerializer(serializers.ModelSerializer):
    class Meta:
        model = DetalleMaterial
        # Se listan los campos explícitamente para no exponer el campo
        # virtual 'pk' (la llave compuesta orden+modelo se ve en sus columnas).
        fields = ['orden', 'modelo', 'cantidad']

        # La llave primaria es compuesta (orden, modelo). DRF no deduce solo
        # esa restricción, así que repetir un modelo en la misma orden llegaba
        # hasta MySQL y reventaba en 500. Validado aquí sale un 400 con motivo.
        #
        # El formulario ya no ofrece los modelos que la orden tiene, así que
        # esto es la red de abajo: cubre a quien llegue por la API directa.
        validators = [
            UniqueTogetherValidator(
                queryset=DetalleMaterial.objects.all(),
                fields=['orden', 'modelo'],
                message='Esa orden ya pide ese modelo: cámbiale la cantidad al material que ya tiene, en lugar de agregarlo otra vez.',
            )
        ]
 
 
class OrdenMaterialDetailSerializer(OrdenMaterialSerializer):
    """Detalle de una orden de material con sus materiales (detalle_material) anidados."""
    detalles = serializers.SerializerMethodField()
 
    def get_detalles(self, obj):
        detalles = DetalleMaterial.objects.filter(orden=obj.numero)
        return DetalleMaterialSerializer(detalles, many=True).data
 
 
# Componente
 
class ComponenteSerializer(serializers.ModelSerializer):
    class Meta:
        model = Componente
        fields = '__all__'
 
 
class VistaComponenteSerializer(serializers.ModelSerializer):
    class Meta:
        model = VistaComponente
        fields = '__all__'