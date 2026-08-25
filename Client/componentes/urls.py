from django.urls import path
from . import views

urlpatterns = [
    # Componentes
    path('', views.componentesListView, name='componentes-lista'),
    path('editar/<int:numero>/', views.componenteEditarView, name='componente-editar'),
    path('baja/<int:numero>/', views.componenteBajaView, name='componente-baja'),

    # Modelos de componente
    path('modelos/', views.modelosListView, name='modelos-lista'),
    path('modelos/editar/<str:codigo>/', views.modeloEditarView, name='modelo-editar'),
    path('modelos/eliminar/<str:codigo>/', views.modeloEliminarView, name='modelo-eliminar'),

    # Lotes
    path('lotes/', views.lotesListView, name='lotes-lista'),
    path('lotes/editar/<str:codigo>/', views.loteEditarView, name='lote-editar'),
    path('lotes/eliminar/<str:codigo>/', views.loteEliminarView, name='lote-eliminar'),

    # Ordenes de material
    path('ordenes/', views.ordenesListView, name='ordenes-lista'),
    path('ordenes/editar/<int:numero>/', views.ordenEditarView, name='orden-editar'),
    path('ordenes/eliminar/<int:numero>/', views.ordenEliminarView, name='orden-eliminar'),
    path('ordenes/<int:numero>/', views.ordenDetalleView, name='orden-detalle'),
    path('ordenes/<int:numero>/material/eliminar/<str:modelo>/', views.materialEliminarView, name='material-eliminar'),
    path('ordenes/<int:numero>/recibir/', views.ordenRecibirView, name='orden-recibir'),
]
