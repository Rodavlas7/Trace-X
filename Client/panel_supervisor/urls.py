"""URLs del panel de supervisor. Van montadas en /panel/supervisor/.

El `app_name` mete todos estos nombres bajo el namespace `panel_supervisor`, así
que desde las plantillas se usan como
{% url 'panel_supervisor:laptops-lista' %}. Gracias a eso este panel puede
nombrar sus pantallas como quiera sin chocar con los otros dos.

Los módulos son los del rol SUPER (ver PERMISOS_ROL en
Servicios/usuarios/permissions.py).
"""

from django.urls import path

from . import views, views_calidad, views_componentes, views_produccion

app_name = 'panel_supervisor'

urlpatterns = [
    path('', views.Dashboard.as_view(), name='dashboard'),

    # Con cuál de sus líneas está trabajando (el selector del menú)
    path('linea/', views.cambiarLineaView, name='cambiar-linea'),

    # ------------------------------------------------------------------
    # P R O D U C C I O N
    # ------------------------------------------------------------------

    # Órdenes de producción
    path('produccion/ordenes/', views_produccion.ordenesProduccionListView, name='ordenes-produccion-lista'),
    path('produccion/ordenes/editar/<int:folio>/', views_produccion.ordenProduccionEditarView, name='orden-produccion-editar'),
    path('produccion/ordenes/cancelar/<int:folio>/', views_produccion.ordenProduccionCancelarView, name='orden-produccion-cancelar'),
    path('produccion/ordenes/iniciar-ensamblaje/<int:folio>/', views_produccion.ordenProduccionIniciarEnsamblajeView, name='orden-produccion-iniciar-ensamblaje'),
    path('produccion/ordenes/<int:folio>/', views_produccion.ordenProduccionDetalleView, name='orden-produccion-detalle'),

    # Laptops
    path('produccion/laptops/', views_produccion.laptopsListView, name='laptops-lista'),
    path('produccion/laptops/editar/<int:numero>/', views_produccion.laptopEditarView, name='laptop-editar'),
    path('produccion/laptops/rechazar/<int:numero>/', views_produccion.laptopRechazarView, name='laptop-rechazar'),
    path('produccion/laptops/<int:numero>/', views_produccion.laptopDetalleView, name='laptop-detalle'),
    path('produccion/laptops/<int:numero>/liberar/<int:componente>/', views_produccion.laptopComponenteLiberarView, name='laptop-componente-liberar'),
    path('produccion/laptops/<int:numero>/desarmar/', views_produccion.laptopDesarmarView, name='laptop-desarmar'),

    # Ensamblaje
    path('produccion/ensamblaje/', views_produccion.ensamblajeSeguimientoView, name='ensamblaje-seguimiento'),
    path('produccion/ensamblaje/registrar/', views_produccion.ensamblajeRegistrarView, name='ensamblaje-registrar'),

    # Paros
    path('produccion/paros/', views_produccion.ListaParos.as_view(), name='lista_paros'),
    path('produccion/paros/crear/', views_produccion.CrearParo.as_view(), name='paro-crear'),
    path('produccion/paros/editar/<int:numero>/', views_produccion.EditarParo.as_view(), name='paro-editar'),
    path('produccion/paros/cerrar/<int:numero>/', views_produccion.CerrarParo.as_view(), name='paro-cerrar'),

    # ------------------------------------------------------------------
    # M A T E R I A L E S
    # ------------------------------------------------------------------

    # Componentes
    path('componentes/', views_componentes.componentesListView, name='componentes-lista'),
    path('componentes/editar/<int:numero>/', views_componentes.componenteEditarView, name='componente-editar'),
    path('componentes/baja/<int:numero>/', views_componentes.componenteBajaView, name='componente-baja'),

    # Modelos de componente
    path('componentes/modelos/', views_componentes.modelosListView, name='modelos-lista'),
    path('componentes/modelos/editar/<str:codigo>/', views_componentes.modeloEditarView, name='modelo-editar'),
    path('componentes/modelos/eliminar/<str:codigo>/', views_componentes.modeloEliminarView, name='modelo-eliminar'),

    # Lotes
    path('componentes/lotes/', views_componentes.lotesListView, name='lotes-lista'),
    path('componentes/lotes/editar/<str:codigo>/', views_componentes.loteEditarView, name='lote-editar'),
    path('componentes/lotes/eliminar/<str:codigo>/', views_componentes.loteEliminarView, name='lote-eliminar'),

    # Órdenes de material
    path('componentes/ordenes/', views_componentes.ordenesListView, name='ordenes-lista'),
    path('componentes/ordenes/editar/<int:numero>/', views_componentes.ordenEditarView, name='orden-editar'),
    path('componentes/ordenes/eliminar/<int:numero>/', views_componentes.ordenEliminarView, name='orden-eliminar'),
    path('componentes/ordenes/<int:numero>/', views_componentes.ordenDetalleView, name='orden-detalle'),
    path('componentes/ordenes/<int:numero>/material/eliminar/<str:modelo>/', views_componentes.materialEliminarView, name='material-eliminar'),
    path('componentes/ordenes/<int:numero>/recibir/', views_componentes.ordenRecibirView, name='orden-recibir'),

    # ------------------------------------------------------------------
    # C A L I D A D
    # ------------------------------------------------------------------

    path('calidad/inspecciones/', views_calidad.ListaInspecciones.as_view(), name='inspecciones'),
    path('calidad/inspecciones/crear/', views_calidad.CrearInspeccion.as_view(), name='inspeccion-crear'),
    path('calidad/inspecciones/editar/<int:numero>/', views_calidad.EditarInspeccion.as_view(), name='inspeccion-editar'),
    path('calidad/inspecciones/eliminar/<int:numero>/', views_calidad.EliminarInspeccion.as_view(), name='inspeccion-eliminar'),
    path('calidad/empleados-calidad-por-linea/<str:linea_id>/', views_calidad.EmpleadosCalidadPorLinea.as_view(), name='empleados-calidad-por-linea'),
]
