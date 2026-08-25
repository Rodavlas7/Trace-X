"""Materiales, versión del panel de supervisor.

Componentes, modelos, lotes y órdenes de material. El panel de administrador
tiene su propia copia en la app `componentes/`; ésta se puede cambiar sin
afectarla.

DIFERENCIA CON EL PANEL DE ADMIN
--------------------------------
El supervisor trabaja una sola línea: la suya. Aquí eso significa dos cosas.

1. Sólo ve el material de su línea. Los componentes y las órdenes de otras
   líneas ni siquiera llegan a la plantilla.
2. Nunca elige la línea. En los formularios no aparece el campo: la vista le
   pone la suya al guardar. Así no puede dar de alta material en una línea que
   no le toca, ni por error ni a propósito.

OJO: esto es del lado del cliente, o sea que es lo que la pantalla enseña y
manda. La API sigue devolviéndole todo a cualquier usuario con permiso del
módulo, así que esto NO sustituye un control de acceso de verdad; ese tendría
que vivir en Servicios, filtrando por la línea del token.
"""

import requests

from django.contrib import messages
from django.shortcuts import render, redirect

from core import lineas as lineas_del_empleado
from core.api import fallo, get, lista, mensaje_error, objeto
from core.filtros import contexto as contexto_de_filtros, filtrar, pedidos, por_codigo
from core.guards import requiere_rol
from core.roles import ROL_SUPERVISOR

# URL base de la API (Servicios). Igual que en home/views.py.
API = "http://127.0.0.1:8000/api"


def _headers(request):
    return {"Authorization": f"Bearer {request.session.get('token')}"}


def _avisar_si_falla(request, respuesta, que):
    """Avisa al usuario cuando la API no entregó los datos.

    Sin esto la pantalla se ve vacía y parece que no hay registros dados de alta,
    cuando en realidad la sesión venció o la API está caída."""
    if fallo(respuesta):
        messages.error(request, f"No se pudieron cargar {que}. {mensaje_error(respuesta)}")


# ==================================================
# L A   L I N E A   D E L   S U P E R V I S O R
# ==================================================


def _mi_linea(request):
    """El código de línea del supervisor, avisándole si no tiene ninguna.

    Sin línea no hay nada que pueda ver ni dar de alta, así que más vale decirlo
    con todas sus letras que dejarlo frente a una pantalla vacía sin explicación."""

    linea = lineas_del_empleado.de_la_sesion(request)

    if not linea:
        messages.error(
            request,
            "No tienes una línea asignada, así que no se puede mostrar material. "
            "Pídele a un administrador que te asigne una."
        )
        return None

    return linea['codigo']


def _solo_de(registros, clave, linea):
    """Deja únicamente los registros de esa línea.

    Si el supervisor no tiene línea no se devuelve nada: mejor una lista vacía
    con su aviso que enseñarle de más."""
    if not linea:
        return []
    return [r for r in registros if r.get(clave) == linea]


def _contexto_de_linea(request):
    """Los datos de la línea del supervisor que las plantillas muestran fijos,
    en lugar del selector que tiene el panel de admin."""
    linea = lineas_del_empleado.de_la_sesion(request) or {}
    return {
        "mi_linea": linea.get("codigo"),
        "mi_linea_nombre": linea.get("nombre"),
    }


def _cuantos_usan(request, clave, linea):
    """Cuántos componentes DE SU LÍNEA usan cada valor de esa columna.

    Es el mismo conteo que en el panel de admin, pero acotado: al supervisor no
    le sirve —ni le toca— saber cuánto se usa un lote en las demás líneas."""
    conteo = {}
    componentes = lista(get(f"{API}/componentes/", _headers(request)))

    for componente in _solo_de(componentes, "linea_codigo", linea):
        valor = componente.get(clave)
        if valor:
            conteo[valor] = conteo.get(valor, 0) + 1

    return conteo


#COMPONENTES

@requiere_rol(ROL_SUPERVISOR)
def componentesListView(request):

    if 'token' not in request.session:
        return redirect('login')

    headers = _headers(request)
    linea = _mi_linea(request)

    if request.method == "POST":

        if not linea:
            return redirect('panel_supervisor:componentes-lista')

        payload = {
            "num_serie": request.POST.get("num_serie") or None,
            "descripcion": request.POST.get("descripcion") or None,
            # La línea no se captura: es la del supervisor.
            "linea": linea,
            "modelo": request.POST.get("modelo") or None,
            "lote": request.POST.get("lote") or None,
            "estado": request.POST.get("estado") or None,
            "orden_material": request.POST.get("orden_material") or None,
            "registro_ensamblaje": request.POST.get("registro_ensamblaje") or None,
        }

        respuesta = requests.post(f"{API}/componentes/", json=payload, headers=headers)

        if respuesta.status_code == 201:
            messages.success(request, "Componente registrado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

        return redirect('panel_supervisor:componentes-lista')

    respuesta_componentes = get(f"{API}/componentes/", headers)

    _avisar_si_falla(request, respuesta_componentes, "los componentes")

    componentes = _solo_de(lista(respuesta_componentes), "linea_codigo", linea)

    # Sin filtro de línea: la línea ya está fija y no hay otras que ver.
    filtros = pedidos(request, "q", "modelo", "lote", "estado")

    filtrados = filtrar(
        componentes,
        filtros,
        exactos=(("modelo", "modelo_codigo"),
                 ("lote", "lote_codigo"),
                 ("estado", "estado_codigo")),
        busqueda=("num_serie", "descripcion", "numero"),
    )

    # Sólo las órdenes de su línea se le pueden asignar a un componente suyo.
    ordenes = _solo_de(lista(get(f"{API}/componentes/ordenes/", headers)), "linea", linea)

    contexto = {
        "componentes": filtrados,
        "modelos": lista(get(f"{API}/componentes/modelos/", headers)),
        "lotes": lista(get(f"{API}/componentes/lotes/", headers)),
        "estados": lista(get(f"{API}/componentes/estados/", headers)),
        "ordenes": ordenes,
    }
    contexto.update(contexto_de_filtros(filtros, componentes, filtrados))
    contexto.update(_contexto_de_linea(request))

    return render(request, "panel_supervisor/componentes/lista.html", contexto)


@requiere_rol(ROL_SUPERVISOR)
def componenteEditarView(request, numero):

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)
        linea = _mi_linea(request)

        if not linea:
            return redirect('panel_supervisor:componentes-lista')

        payload = {
            "num_serie": request.POST.get("num_serie") or None,
            "descripcion": request.POST.get("descripcion") or None,
            # Se reafirma su línea: un componente suyo no se puede mandar a otra.
            "linea": linea,
            "modelo": request.POST.get("modelo") or None,
            "lote": request.POST.get("lote") or None,
            "estado": request.POST.get("estado") or None,
            "orden_material": request.POST.get("orden_material") or None,
            "registro_ensamblaje": request.POST.get("registro_ensamblaje") or None,
        }

        respuesta = requests.put(f"{API}/componentes/mod/{numero}/", json=payload, headers=headers)

        if respuesta.status_code == 200:
            messages.success(request, "Componente actualizado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

    return redirect('panel_supervisor:componentes-lista')


@requiere_rol(ROL_SUPERVISOR)
def componenteBajaView(request, numero):
    """El DELETE de la API no borra el registro: lo marca como Mermado."""

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)
        respuesta = requests.delete(f"{API}/componentes/mod/{numero}/", headers=headers)

        if respuesta.status_code == 204:
            messages.success(request, "Componente marcado como Mermado.")
        else:
            messages.error(request, mensaje_error(respuesta))

    return redirect('panel_supervisor:componentes-lista')



# MODELOS DE COMPONENTE
#
# Los modelos y los lotes son catálogos de toda la planta, no de una línea, así
# que el supervisor los ve completos. Lo único acotado es el conteo de "en uso",
# que cuenta nada más los componentes de su línea.


@requiere_rol(ROL_SUPERVISOR)
def modelosListView(request):

    if 'token' not in request.session:
        return redirect('login')

    headers = _headers(request)

    if request.method == "POST":

        payload = {
            "codigo": request.POST.get("codigo"),
            "nombre": request.POST.get("nombre") or None,
            "tipo_componente": request.POST.get("tipo_componente") or None,
            "fabricante": request.POST.get("fabricante") or None,
        }

        respuesta = requests.post(f"{API}/componentes/modelos/", json=payload, headers=headers)

        if respuesta.status_code == 201:
            messages.success(request, "Modelo de componente registrado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

        return redirect('panel_supervisor:modelos-lista')

    respuesta_modelos = get(f"{API}/componentes/modelos/", headers)

    _avisar_si_falla(request, respuesta_modelos, "los modelos")

    linea = _mi_linea(request)
    tipos = lista(get(f"{API}/componentes/tipos/", headers))
    tipos_por_codigo = por_codigo(tipos)
    en_uso = _cuantos_usan(request, "modelo_codigo", linea)

    # La API devuelve el tipo como código (TC001). En pantalla se quiere el
    # nombre, así que se resuelve aquí contra el catálogo que ya se pidió.
    modelos = lista(respuesta_modelos)
    for modelo in modelos:
        tipo = tipos_por_codigo.get(modelo.get("tipo_componente")) or {}
        modelo["tipo_nombre"] = tipo.get("nombre")
        modelo["componentes"] = en_uso.get(modelo.get("codigo"), 0)

    filtros = pedidos(request, "q", "tipo", "fabricante")

    filtrados = filtrar(
        modelos,
        filtros,
        exactos=(("tipo", "tipo_componente"),
                 ("fabricante", "fabricante")),
        busqueda=("codigo", "nombre", "fabricante", "tipo_nombre"),
    )

    contexto = {
        "modelos": filtrados,
        "tipos": tipos,
        # El fabricante es texto libre, no un catálogo: las opciones del filtro
        # salen de lo que de verdad hay capturado.
        "fabricantes": sorted({m["fabricante"] for m in modelos if m.get("fabricante")}),
    }
    contexto.update(contexto_de_filtros(filtros, modelos, filtrados))
    contexto.update(_contexto_de_linea(request))

    return render(request, "panel_supervisor/componentes/modelos.html", contexto)


@requiere_rol(ROL_SUPERVISOR)
def modeloEditarView(request, codigo):

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)

        payload = {
            "nombre": request.POST.get("nombre") or None,
            "tipo_componente": request.POST.get("tipo_componente") or None,
            "fabricante": request.POST.get("fabricante") or None,
        }

        respuesta = requests.put(f"{API}/componentes/modelos/mod/{codigo}/", json=payload, headers=headers)

        if respuesta.status_code == 200:
            messages.success(request, "Modelo actualizado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

    return redirect('panel_supervisor:modelos-lista')


@requiere_rol(ROL_SUPERVISOR)
def modeloEliminarView(request, codigo):

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)
        respuesta = requests.delete(f"{API}/componentes/modelos/mod/{codigo}/", headers=headers)

        if respuesta.status_code == 204:
            messages.success(request, "Modelo eliminado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

    return redirect('panel_supervisor:modelos-lista')


# LOTES DE COMPONENTE

@requiere_rol(ROL_SUPERVISOR)
def lotesListView(request):

    if 'token' not in request.session:
        return redirect('login')

    headers = _headers(request)

    if request.method == "POST":

        payload = {
            "codigo": request.POST.get("codigo"),
            "descripcion": request.POST.get("descripcion") or None,
        }

        respuesta = requests.post(f"{API}/componentes/lotes/", json=payload, headers=headers)

        if respuesta.status_code == 201:
            messages.success(request, "Lote registrado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

        return redirect('panel_supervisor:lotes-lista')

    respuesta_lotes = get(f"{API}/componentes/lotes/", headers)

    _avisar_si_falla(request, respuesta_lotes, "los lotes")

    linea = _mi_linea(request)
    en_uso = _cuantos_usan(request, "lote_codigo", linea)

    lotes = lista(respuesta_lotes)
    for lote in lotes:
        lote["componentes"] = en_uso.get(lote.get("codigo"), 0)

    filtros = pedidos(request, "q")
    filtrados = filtrar(lotes, filtros, busqueda=("codigo", "descripcion"))

    contexto = {"lotes": filtrados}
    contexto.update(contexto_de_filtros(filtros, lotes, filtrados))
    contexto.update(_contexto_de_linea(request))

    return render(request, "panel_supervisor/componentes/lotes.html", contexto)


@requiere_rol(ROL_SUPERVISOR)
def loteEditarView(request, codigo):

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)
        payload = {"descripcion": request.POST.get("descripcion") or None}

        respuesta = requests.put(f"{API}/componentes/lotes/mod/{codigo}/", json=payload, headers=headers)

        if respuesta.status_code == 200:
            messages.success(request, "Lote actualizado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

    return redirect('panel_supervisor:lotes-lista')


@requiere_rol(ROL_SUPERVISOR)
def loteEliminarView(request, codigo):

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)
        respuesta = requests.delete(f"{API}/componentes/lotes/mod/{codigo}/", headers=headers)

        if respuesta.status_code == 204:
            messages.success(request, "Lote eliminado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

    return redirect('panel_supervisor:lotes-lista')


#  ORDENES DE MATERIAL

def _necesitada(request):
    """Junta los dos campos del formulario en el DATETIME que espera la API.

    Se capturan por separado —<input type="date"> y <input type="time">— y no
    con un solo datetime-local porque el selector de ése nada más abre el
    calendario: la hora hay que teclearla a mano. Dos campos dan los dos menús.

    Sin fecha no hay nada que mandar y va None: la columna admite NULL. Si viene
    la fecha pero no la hora se asume el arranque del día, que es lo que
    entiende cualquiera al escribir sólo un día.
    """
    fecha = request.POST.get("necesitada_fecha")
    hora = request.POST.get("necesitada_hora")

    if not fecha:
        return None

    return f"{fecha}T{hora or '00:00'}"



@requiere_rol(ROL_SUPERVISOR)
def ordenesListView(request):

    if 'token' not in request.session:
        return redirect('login')

    headers = _headers(request)
    linea = _mi_linea(request)

    if request.method == "POST":

        if not linea:
            return redirect('panel_supervisor:ordenes-lista')

        # 'solicitud' no se manda: la sella la API con la hora del servidor.
        # 'recepcion' tampoco: la escribe el procedimiento al recibir.
        payload = {
            "necesitada": _necesitada(request),
            # La línea no se captura: la orden es para surtir la suya.
            "linea": linea,
        }

        respuesta = requests.post(f"{API}/componentes/ordenes/", json=payload, headers=headers)

        if respuesta.status_code == 201:
            messages.success(request, "Orden de material registrada correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

        return redirect('panel_supervisor:ordenes-lista')

    respuesta_ordenes = get(f"{API}/componentes/ordenes/", headers)

    _avisar_si_falla(request, respuesta_ordenes, "las órdenes de material")

    ordenes = _solo_de(lista(respuesta_ordenes), "linea", linea)

    # Cuántos materiales trae cada orden. La API los devuelve todos juntos, así
    # que se cuentan de una sola pasada en lugar de pedir orden por orden.
    materiales = {}
    for detalle in lista(get(f"{API}/componentes/detalles/", headers)):
        clave = str(detalle.get("orden"))
        materiales[clave] = materiales.get(clave, 0) + 1

    for orden in ordenes:
        orden["materiales"] = materiales.get(str(orden.get("numero")), 0)
        orden["recibida"] = bool(orden.get("recepcion"))

    # Sin filtro de línea: todas las que ve son de la suya.
    filtros = pedidos(request, "q", "desde", "hasta")

    filtradas = filtrar(ordenes, filtros, busqueda=("numero",))

    # El rango de fechas no es una coincidencia exacta, va aparte. Las fechas
    # llegan como AAAA-MM-DD, que se ordena bien comparándolas como texto.
    if filtros["desde"]:
        filtradas = [o for o in filtradas if (o.get("solicitud") or "")[:10] >= filtros["desde"]]
    if filtros["hasta"]:
        filtradas = [o for o in filtradas if (o.get("solicitud") or "")[:10] <= filtros["hasta"]]

    contexto = {"ordenes": filtradas}
    contexto.update(contexto_de_filtros(filtros, ordenes, filtradas))
    contexto.update(_contexto_de_linea(request))

    return render(request, "panel_supervisor/componentes/ordenes.html", contexto)


@requiere_rol(ROL_SUPERVISOR)
def ordenEditarView(request, numero):

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)
        linea = _mi_linea(request)

        if not linea:
            return redirect('panel_supervisor:ordenes-lista')

        payload = {
            "necesitada": _necesitada(request),
            # Se reafirma su línea: la orden no se puede pasar a otra.
            "linea": linea,
        }

        respuesta = requests.put(f"{API}/componentes/ordenes/mod/{numero}/", json=payload, headers=headers)

        if respuesta.status_code == 200:
            messages.success(request, "Orden actualizada correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

    return redirect('panel_supervisor:ordenes-lista')


@requiere_rol(ROL_SUPERVISOR)
def ordenEliminarView(request, numero):

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)
        respuesta = requests.delete(f"{API}/componentes/ordenes/mod/{numero}/", headers=headers)

        if respuesta.status_code == 204:
            messages.success(request, "Orden eliminada correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

    return redirect('panel_supervisor:ordenes-lista')


@requiere_rol(ROL_SUPERVISOR)
def ordenDetalleView(request, numero):
    """Materiales (detalle_material) de una orden de material."""

    if 'token' not in request.session:
        return redirect('login')

    headers = _headers(request)

    if request.method == "POST":

        payload = {
            "orden": numero,
            "modelo": request.POST.get("modelo") or None,
            "cantidad": request.POST.get("cantidad") or None,
        }

        respuesta = requests.post(f"{API}/componentes/detalles/", json=payload, headers=headers)

        if respuesta.status_code == 201:
            messages.success(request, "Material agregado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

        return redirect('panel_supervisor:orden-detalle', numero=numero)

    respuesta_orden = get(f"{API}/componentes/ordenes/{numero}/", headers)

    # En un detalle no hay nada que pintar si la API falla: se regresa a la lista
    # con el motivo en lugar de una pantalla de campos en blanco.
    if fallo(respuesta_orden):
        messages.error(request, f"No se pudo cargar la orden {numero}. {mensaje_error(respuesta_orden)}")
        return redirect('panel_supervisor:ordenes-lista')

    orden = objeto(respuesta_orden)
    linea = _mi_linea(request)

    # La lista filtra por línea, pero a esta pantalla se llega por URL: sin esto
    # un supervisor podría leer los materiales de la orden de otra línea a mano.
    if orden.get("linea") != linea:
        messages.error(request, "Esa orden de material no es de tu línea.")
        return redirect('panel_supervisor:ordenes-lista')

    modelos = lista(get(f"{API}/componentes/modelos/", headers))
    modelos_por_codigo = por_codigo(modelos)

    # Los materiales vienen con el código del modelo; en pantalla se acompaña del
    # nombre para no obligar a nadie a memorizarse el catálogo.
    for material in orden.get("detalles") or []:
        modelo = modelos_por_codigo.get(material.get("modelo")) or {}
        material["modelo_nombre"] = modelo.get("nombre")

    # El combo de "Agregar material" sólo ofrece lo que esa línea sabe ensamblar,
    # y sale del mismo catálogo con el que el trigger rechaza lo que no toca
    # (estacion_compatibilidad_componente). Antes ofrecía los 31 modelos del
    # catálogo y la base tumbaba la mayoría, así que el error se descubría hasta
    # darle guardar.
    compatibles = lista(get(f"{API}/componentes/compatibilidad-linea/", headers,
                            params={"linea": orden.get("linea")}))

    # Y de ésos, los que la orden todavía no pide. La llave de detalle_material
    # es (orden, modelo), así que un modelo repetido no es una cantidad mayor:
    # es un 400 por duplicado. Ofrecerlo era ofrecer un error.
    #
    # Se mandan las dos listas porque el combo vacío tiene dos motivos muy
    # distintos —la línea no ensambla nada, o ya se pidió todo lo que ensambla—
    # y la plantilla los explica por separado.
    ya_en_la_orden = {d.get("modelo") for d in orden.get("detalles") or []}
    disponibles = [m for m in compatibles if m.get("codigo") not in ya_en_la_orden]

    # Los lotes son para el modal de recibir: con cuál entran las piezas.
    lotes = lista(get(f"{API}/componentes/lotes/", headers))

    contexto = {"orden": orden, "modelos": modelos, "compatibles": compatibles, "disponibles": disponibles, "lotes": lotes}
    contexto.update(_contexto_de_linea(request))

    return render(request, "panel_supervisor/componentes/orden_detalle.html", contexto)


@requiere_rol(ROL_SUPERVISOR)
def materialEliminarView(request, numero, modelo):

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)
        respuesta = requests.delete(f"{API}/componentes/detalles/mod/{numero}/{modelo}/", headers=headers)

        if respuesta.status_code == 204:
            messages.success(request, "Material eliminado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

    return redirect('panel_supervisor:orden-detalle', numero=numero)


@requiere_rol(ROL_SUPERVISOR)
def ordenRecibirView(request, numero):
    """Convierte los materiales de la orden en piezas físicas de inventario.

    Antes esto era capturar componente por componente desde la pantalla de
    materiales: cincuenta piezas eran cincuenta altas a mano, cada una su propia
    transacción. Ahora lo resuelve sp_Recibir_Orden_Material, que da de alta lo
    que falte de cada material en una sola transacción.

    Se puede volver a llamar: el procedimiento siempre mira cuántas faltan, así
    que sirve para cuando el proveedor manda incompleto y luego completa.

    La línea no se manda: el procedimiento usa la de la orden."""

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)
        respuesta = requests.post(
            f"{API}/componentes/ordenes/{numero}/recibir/",
            json={"lote": request.POST.get("lote") or None},
            headers=headers,
        )

        if respuesta.status_code == 200:
            resumen = respuesta.json()
            pendientes = resumen.get('componentes_pendientes') or 0

            # El procedimiento sólo sella la orden cuando ya no falta nada. Si
            # quedó algo pendiente hay que decirlo: la orden sigue abierta y se
            # puede volver a recibir cuando el proveedor complete.
            if pendientes:
                cierre = f". Faltan {pendientes} pieza(s) por recibir, la orden sigue abierta."
            else:
                cierre = ". La orden quedó completa y se marcó como recibida."

            messages.success(
                request,
                f"Se recibieron {resumen.get('componentes_creados', 0)} pieza(s) "
                f"de la orden #{numero}, disponibles en {resumen.get('linea')}"
                + (f". Ya se habían recibido {resumen['componentes_previos']} antes"
                   if resumen.get('componentes_previos') else "")
                + cierre
            )
        else:
            messages.error(request, mensaje_error(respuesta))

    return redirect('panel_supervisor:orden-detalle', numero=numero)
