from django.shortcuts import get_object_or_404
from rest_framework import generics
from api.errores import ErroresDeBaseMixin
from api.views import AccionDeProcedimientoAPIView
from .models import *
from .serializers import *
from rest_framework.permissions import IsAuthenticated
from usuarios.permissions import TienePermisoModulo
# Create your views here.

''' AQUI ESTAN LOS VIEWS DE:
│   - TipoComp (catálogo, solo lectura)
│   - EdoComponente (catálogo, solo lectura)
│   - LoteComp (catálogo: crear / modificar / eliminar)
│   - ModeloComponente (catálogo: crear / modificar / eliminar)
│   - OrdenMaterial + DetalleMaterial (crear / modificar / eliminar / recibir)
│   - VistaComponente (consulta general, lee de la vista SQL vista_componentes)
│   - Componente (crear / modificar / eliminar=marcar como Mermado)
'''
 
# Código de estado usado para el "soft delete" de un componente.
# EDC004 = Mermado (ver DB/datos.sql, tabla edo_componente).
ESTADO_MERMADO = 'EDC004'


# El manejo de los errores de la base (ErroresDeBaseMixin) vive en
# api/errores.py: lo comparten todos los módulos de la API.


# Vistas de catálogos (solo lectura)
 
class TipoCompListAPIView(generics.ListAPIView):
    permission_classes = [
        IsAuthenticated,
        TienePermisoModulo
    ]
    modulo = "componentes"
    
    queryset = TipoComp.objects.all()
    serializer_class = TipoCompSerializer
 
 
class EdoComponenteListAPIView(generics.ListAPIView):
    permission_classes = [
            IsAuthenticated,
            TienePermisoModulo
        ]
    modulo = "componentes"
        
    queryset = EdoComponente.objects.all()
    serializer_class = EdoComponenteSerializer
 
 
# Vistas de LOTE_COMP
 
class LoteCompListCreateAPIView(ErroresDeBaseMixin, generics.ListCreateAPIView):
    permission_classes = [
            IsAuthenticated,
            TienePermisoModulo
        ]
    modulo = "componentes"
    queryset = LoteComp.objects.all()
    serializer_class = LoteCompSerializer


class LoteCompDetailAPIView(generics.RetrieveAPIView):
    permission_classes = [
            IsAuthenticated,
            TienePermisoModulo
        ]
    modulo = "componentes"
    queryset = LoteComp.objects.all()
    serializer_class = LoteCompSerializer
    lookup_field = 'codigo'
 
 
class LoteCompModifyAPIView(ErroresDeBaseMixin, generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [
            IsAuthenticated,
            TienePermisoModulo
        ]
    modulo = "componentes"
    queryset = LoteComp.objects.all()
    # Al editar, el codigo lo manda la URL y no se toca (ver serializers.py).
    serializer_class = LoteCompUpdateSerializer
    lookup_field = 'codigo'


# Vistas de MODELO_COMPONENTE

class ModeloComponenteListCreateAPIView(ErroresDeBaseMixin, generics.ListCreateAPIView):
    permission_classes = [
            IsAuthenticated,
            TienePermisoModulo
        ]
    modulo = "componentes"
    queryset = ModeloComponente.objects.all()
    serializer_class = ModeloComponenteSerializer
 
 
class ModeloComponenteDetailAPIView(generics.RetrieveAPIView):
    permission_classes = [
            IsAuthenticated,
            TienePermisoModulo
        ]
    modulo = "componentes"
    queryset = ModeloComponente.objects.all()
    serializer_class = ModeloComponenteSerializer
    lookup_field = 'codigo'
 
 
class ModeloComponenteModifyAPIView(ErroresDeBaseMixin, generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [
            IsAuthenticated,
            TienePermisoModulo
        ]
    modulo = "componentes"

    queryset = ModeloComponente.objects.all()
    # Al editar, el codigo lo manda la URL y no se toca (ver serializers.py).
    serializer_class = ModeloComponenteUpdateSerializer
    lookup_field = 'codigo'


# Vistas de MODELO_LAPTOP_COMPONENTE (tabla puente / lista de materiales)

class ModeloLaptopComponenteListCreateAPIView(ErroresDeBaseMixin, generics.ListCreateAPIView):
    """GET: todos los renglones. Filtra por modelo de laptop con
    ?modelo_laptop=<codigo>.  POST: agrega un componente (con su capacidad)
    a un modelo de laptop."""
    permission_classes = [
            IsAuthenticated,
            TienePermisoModulo
        ]
    modulo = "componentes"
    
    serializer_class = ModeloLaptopComponenteSerializer

    def get_queryset(self):
        queryset = ModeloLaptopComponente.objects.all()
        modelo_laptop = self.request.query_params.get('modelo_laptop')
        if modelo_laptop is not None:
            queryset = queryset.filter(modelo_laptop=modelo_laptop)
        return queryset


class ModeloLaptopComponenteModifyAPIView(ErroresDeBaseMixin, generics.RetrieveUpdateDestroyAPIView):
    """Modifica/borra un renglón del BOM. Se direcciona por la llave
    compuesta (modelo_laptop, modelo_componente)."""
    permission_classes = [
            IsAuthenticated,
            TienePermisoModulo
        ]
    modulo = "componentes"
    serializer_class = ModeloLaptopComponenteSerializer

    def get_object(self):
        obj = get_object_or_404(
            ModeloLaptopComponente,
            modelo_laptop=self.kwargs['modelo_laptop'],
            modelo_componente=self.kwargs['modelo_componente'],
        )
        self.check_object_permissions(self.request, obj)
        return obj



class ModelosCompatiblesLineaAPIView(generics.ListAPIView):
    """Qué modelos de componente puede pedir una línea.

    Se filtra con ?linea=LIN001. Devuelve ModeloComponente —la misma forma que
    /componentes/modelos/— para que el formulario de la orden pueda cambiar una
    lista por la otra sin tocar nada más.

    Sale de estacion_compatibilidad_componente, el mismo catálogo que usan los
    triggers para rechazar un material que la línea no ensambla. Que salgan de
    la misma fuente es el punto: hasta ahora el combo ofrecía los 31 modelos y
    la base rechazaba la mayoría, así que el error se descubría al guardar.

    DISTINTAS estaciones de una línea pueden montar el mismo modelo (LIN004
    tiene 10 filas para 7 modelos), de ahí el __in contra la subconsulta en vez
    de un JOIN: así el modelo sale una sola vez.

    Sin ?linea devuelve el catálogo completo, que es lo correcto para una orden
    que todavía no tiene línea: ahí el trigger tampoco compara contra nada.

    OJO, no es lo mismo que /componentes/compatibilidad/, que es el BOM
    (modelo_laptop_componente): qué piezas lleva una laptop, no qué piezas sabe
    montar una línea.
    """

    permission_classes = [
            IsAuthenticated,
            TienePermisoModulo
        ]
    modulo = "orden_material"
    serializer_class = ModeloComponenteSerializer

    def get_queryset(self):
        modelos = ModeloComponente.objects.all()
        linea = self.request.query_params.get('linea')

        if linea:
            modelos = modelos.filter(
                codigo__in=EstacionCompatibilidadComponente.objects
                            .filter(estacion__linea=linea)
                            .values('modelo_componente')
            )

        return modelos.order_by('codigo')


# Vistas de ORDEN_MATERIAL / DETALLE_MATERIAL

 
class OrdenMaterialListCreateAPIView(ErroresDeBaseMixin, generics.ListCreateAPIView):
    permission_classes = [
            IsAuthenticated,
            TienePermisoModulo
        ]
    modulo = "orden_material"
    queryset = OrdenMaterial.objects.all()
    serializer_class = OrdenMaterialSerializer
 
 
class OrdenMaterialDetailAPIView(generics.RetrieveAPIView):
    """GET: detalle de la orden de material con sus materiales (detalle_material) anidados."""
    permission_classes = [
                IsAuthenticated,
                TienePermisoModulo
            ]
    modulo = "orden_material"
    queryset = OrdenMaterial.objects.all()
    serializer_class = OrdenMaterialDetailSerializer
    lookup_field = 'numero'
 
 
class OrdenMaterialModifyAPIView(ErroresDeBaseMixin, generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [
                IsAuthenticated,
                TienePermisoModulo
            ]
    modulo = "orden_material"
    queryset = OrdenMaterial.objects.all()
    serializer_class = OrdenMaterialSerializer
    lookup_field = 'numero'
 
 
class DetalleMaterialListCreateAPIView(ErroresDeBaseMixin, generics.ListCreateAPIView):
    """GET: todos los materiales. Filtra por orden con ?orden=<numero>.
    POST: agrega un material (modelo + cantidad) a una orden de material."""
    permission_classes = [
                IsAuthenticated,
                TienePermisoModulo
            ]
    modulo = "orden_material"
    serializer_class = DetalleMaterialSerializer
 
    def get_queryset(self):
        queryset = DetalleMaterial.objects.all()
        orden = self.request.query_params.get('orden')
        if orden is not None:
            queryset = queryset.filter(orden=orden)
        return queryset
 
 
class DetalleMaterialModifyAPIView(ErroresDeBaseMixin, generics.RetrieveUpdateDestroyAPIView):
    """PUT/PATCH modifican la cantidad; DELETE borra el material.
    Se direcciona por la llave compuesta (orden, modelo), ya que la tabla
    detalle_material no tiene un id simple."""
    permission_classes = [
                IsAuthenticated,
                TienePermisoModulo
            ]
    modulo = "orden_material"
    serializer_class = DetalleMaterialSerializer

    def get_object(self):
        obj = get_object_or_404(
            DetalleMaterial,
            orden=self.kwargs['orden'],
            modelo=self.kwargs['modelo'],
        )
        self.check_object_permissions(self.request, obj)
        return obj


# ==================================================
# A C C I O N E S   ( P R O C E D I M I E N T O S )
# ==================================================
#
# Recibir una orden de material no es CRUD sobre una tabla: son N altas de
# componente derivadas de sus materiales, y tienen que pasar o no pasar
# completas. Lo resuelve la base con un procedimiento (DB/procedimientos.sql) y
# aquí sólo se dispara la llamada. La clase base vive en api/views.py.


class RecibirOrdenMaterialAPIView(AccionDeProcedimientoAPIView):
    """Da de alta las piezas que le faltan a la orden de material.

    Por cada material crea los componentes que falten para llegar a la cantidad
    pedida y los deja Disponibles en la línea de la orden. Admite recepción
    parcial: se puede llamar otra vez cuando el proveedor complete.

    'lote' es el lote de componentes (lote_comp) con el que entran las piezas;
    si no viene, entran sin lote."""

    modulo = "orden_material"
    procedimiento = "sp_Recibir_Orden_Material" #AQUI SE LLAMA UN PROCEDIMIENTO

    def argumentos(self, request, numero=None):
        return (numero, request.data.get('lote') or None)


# Vistas de COMPONENTE
 
class ComponenteListAPIView(ErroresDeBaseMixin, generics.ListCreateAPIView):
    """GET: consulta general del módulo (lee de la vista SQL vista_componentes).
    POST: registra un nuevo componente."""
    permission_classes = [
                IsAuthenticated,
                TienePermisoModulo
            ]
    modulo = "componentes"
 
    def get_queryset(self):
        if self.request.method == 'POST':
            return Componente.objects.all()
        return VistaComponente.objects.all()
 
    def get_serializer_class(self):
        if self.request.method == 'POST':
            return ComponenteSerializer
        return VistaComponenteSerializer
 
 
class ComponenteDetailAPIView(generics.RetrieveAPIView):
    """GET: vista detallada de un componente (lee de la vista SQL vista_componentes)."""
    permission_classes = [
                IsAuthenticated,
                TienePermisoModulo
            ]
    modulo = "componentes"
    queryset = VistaComponente.objects.all()
    serializer_class = VistaComponenteSerializer
    lookup_field = 'numero'
 
 
class ComponenteModifyAPIView(ErroresDeBaseMixin, generics.RetrieveUpdateDestroyAPIView):
    """PUT/PATCH modifican el componente; DELETE lo marca como Mermado (EDC004)
    en lugar de borrar el registro físicamente."""
    permission_classes = [
                    IsAuthenticated,
                    TienePermisoModulo
                ]
    modulo = "componentes"
    queryset = Componente.objects.all()
    serializer_class = ComponenteSerializer
    lookup_field = 'numero'
 
    def perform_destroy(self, instance):
        # Reemplaza al perform_destroy del mixin (la baja no borra, marca), así
        # que el guardado se pasa por _intentar para no perder la traducción del
        # error de la base.
        def marcar_como_mermado(componente):
            componente.estado_id = ESTADO_MERMADO
            componente.save(update_fields=['estado'])

        self._intentar(marcar_como_mermado, instance)