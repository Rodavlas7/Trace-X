import requests

from django.contrib import messages
from django.shortcuts import render, redirect

from core.api import fallo, get, lista, mensaje_error, objeto
from core.filtros import contexto as _contexto_de_filtros, filtrar as _filtrar, pedidos as _pedidos, por_codigo as _por_codigo

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


# Los helpers de filtrado viven en core/filtros.py: los comparten los tres
# paneles. Aquí sólo queda lo que es propio de componentes.


def _cuantos_usan(headers, clave):
    """Cuántos componentes usan cada valor de esa columna de vista_componentes.

    Se muestra en las pantallas de lotes y modelos porque explica por adelantado
    lo que si no sólo se descubre al intentar borrar: un catálogo que alguien
    está usando no se puede eliminar."""
    conteo = {}
    for componente in lista(get(f"{API}/componentes/", headers)):
        valor = componente.get(clave)
        if valor:
            conteo[valor] = conteo.get(valor, 0) + 1
    return conteo


#COMPONENTES

def componentesListView(request):

    if 'token' not in request.session:
        return redirect('login')

    headers = _headers(request)

    if request.method == "POST":

        payload = {
            "num_serie": request.POST.get("num_serie") or None,
            "descripcion": request.POST.get("descripcion") or None,
            "linea": request.POST.get("linea") or None,
            "modelo": request.POST.get("modelo") or None,
            "lote": request.POST.get("lote") or None,
            "estado": request.POST.get("estado") or None,
            "orden_material": request.POST.get("orden_material") or None,
            "registro_ensamblaje": request.POST.get("registro_ensamblaje") or None,
        }

        respuesta = requests.post(f"{API}/componentes/", json=payload, headers=headers)

        if respuesta.status_code == 201:
            datos = respuesta.json()
            numero = datos.get("numero") or datos.get("id") or datos.get("codigo")
            if numero:
                messages.success(request, f"Componente registrado correctamente. Número: {numero}")
            else:
                messages.success(request, "Componente registrado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

        return redirect('componentes-lista')

    respuesta_componentes = get(f"{API}/componentes/", headers)

    _avisar_si_falla(request, respuesta_componentes, "los componentes")

    componentes = lista(respuesta_componentes)

    filtros = _pedidos(request, "q", "modelo", "lote", "linea", "estado")

    filtrados = _filtrar(
        componentes,
        filtros,
        exactos=(("modelo", "modelo_codigo"),
                 ("lote", "lote_codigo"),
                 ("linea", "linea_codigo"),
                 ("estado", "estado_codigo")),
        busqueda=("num_serie", "descripcion", "numero"),
    )

    contexto = {
        "componentes": filtrados,
        "lineas": lista(get(f"{API}/lineas/", headers)),
        "modelos": lista(get(f"{API}/componentes/modelos/", headers)),
        "lotes": lista(get(f"{API}/componentes/lotes/", headers)),
        "estados": lista(get(f"{API}/componentes/estados/", headers)),
    }
    contexto.update(_contexto_de_filtros(filtros, componentes, filtrados))

    return render(request, "componentes/lista.html", contexto)


def componenteEditarView(request, numero):

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)

        payload = {
            "num_serie": request.POST.get("num_serie") or None,
            "descripcion": request.POST.get("descripcion") or None,
            "linea": request.POST.get("linea") or None,
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

    return redirect('componentes-lista')


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

    return redirect('componentes-lista')



# MODELOS DE COMPONENTE


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
            datos = respuesta.json()
            numero = datos.get("numero") or datos.get("id") or datos.get("codigo")
            if numero:
                messages.success(request, f"Modelo de componente registrado correctamente. Código: {numero}")
            else:
                messages.success(request, "Modelo de componente registrado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

        return redirect('modelos-lista')

    respuesta_modelos = get(f"{API}/componentes/modelos/", headers)

    _avisar_si_falla(request, respuesta_modelos, "los modelos")

    tipos = lista(get(f"{API}/componentes/tipos/", headers))
    tipos_por_codigo = _por_codigo(tipos)

    en_uso = _cuantos_usan(headers, "modelo_codigo")

    # La API devuelve el tipo como código (TC001). En pantalla se quiere el
    # nombre, así que se resuelve aquí contra el catálogo que ya se pidió.
    modelos = lista(respuesta_modelos)
    for modelo in modelos:
        tipo = tipos_por_codigo.get(modelo.get("tipo_componente")) or {}
        modelo["tipo_nombre"] = tipo.get("nombre")
        modelo["componentes"] = en_uso.get(modelo.get("codigo"), 0)

    filtros = _pedidos(request, "q", "tipo", "fabricante")

    filtrados = _filtrar(
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
    contexto.update(_contexto_de_filtros(filtros, modelos, filtrados))

    return render(request, "componentes/modelos.html", contexto)


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

    return redirect('modelos-lista')


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

    return redirect('modelos-lista')


# LOTES DE COMPONENTE

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
            datos = respuesta.json()
            numero = datos.get("numero") or datos.get("id") or datos.get("codigo")
            if numero:
                messages.success(request, f"Lote registrado correctamente. Número: {numero}")
            else:
                messages.success(request, "Lote registrado correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

        return redirect('lotes-lista')

    respuesta_lotes = get(f"{API}/componentes/lotes/", headers)

    _avisar_si_falla(request, respuesta_lotes, "los lotes")

    en_uso = _cuantos_usan(headers, "lote_codigo")

    lotes = lista(respuesta_lotes)
    for lote in lotes:
        lote["componentes"] = en_uso.get(lote.get("codigo"), 0)

    filtros = _pedidos(request, "q")
    filtrados = _filtrar(lotes, filtros, busqueda=("codigo", "descripcion"))

    contexto = {"lotes": filtrados}
    contexto.update(_contexto_de_filtros(filtros, lotes, filtrados))

    return render(request, "componentes/lotes.html", contexto)


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

    return redirect('lotes-lista')


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

    return redirect('lotes-lista')


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



def ordenesListView(request):

    if 'token' not in request.session:
        return redirect('login')

    headers = _headers(request)

    if request.method == "POST":

        payload = {
            "necesitada": _necesitada(request),
            "linea": request.POST.get("linea") or None,
        }

        respuesta = requests.post(f"{API}/componentes/ordenes/", json=payload, headers=headers)

        if respuesta.status_code == 201:
            datos = respuesta.json()
            numero = datos.get("numero") or datos.get("id") or datos.get("codigo")
            if numero:
                messages.success(request, f"Orden de material registrada correctamente. Número: {numero}")
            else:
                messages.success(request, "Orden de material registrada correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

        return redirect('ordenes-lista')

    respuesta_ordenes = get(f"{API}/componentes/ordenes/", headers)

    _avisar_si_falla(request, respuesta_ordenes, "las órdenes de material")

    lineas = lista(get(f"{API}/lineas/", headers))
    lineas_por_codigo = _por_codigo(lineas)

    # Cuántos materiales trae cada orden. La API los devuelve todos juntos, así
    # que se cuentan de una sola pasada en lugar de pedir orden por orden.
    materiales = {}
    for detalle in lista(get(f"{API}/componentes/detalles/", headers)):
        clave = str(detalle.get("orden"))
        materiales[clave] = materiales.get(clave, 0) + 1

    ordenes = lista(respuesta_ordenes)
    for orden in ordenes:
        linea = lineas_por_codigo.get(orden.get("linea")) or {}
        orden["linea_nombre"] = linea.get("nombre")
        orden["materiales"] = materiales.get(str(orden.get("numero")), 0)
        orden["recibida"] = bool(orden.get("recepcion"))

    filtros = _pedidos(request, "q", "linea", "desde", "hasta")

    filtradas = _filtrar(
        ordenes,
        filtros,
        exactos=(("linea", "linea"),),
        busqueda=("numero", "linea_nombre"),
    )

    # El rango de fechas no es una coincidencia exacta, va aparte. Se filtra por
    # la fecha de solicitud, que es la que ordena la lista.
    #
    # `solicitud` es un DATETIME y llega como '2026-08-25T14:30:00', así que se
    # recorta a los primeros 10 caracteres antes de comparar: contra un 'hasta'
    # de '2026-08-25' la cadena completa sale MAYOR por la hora que trae pegada,
    # y la orden del propio día se caía del resultado.
    if filtros["desde"]:
        filtradas = [o for o in filtradas if (o.get("solicitud") or "")[:10] >= filtros["desde"]]
    if filtros["hasta"]:
        filtradas = [o for o in filtradas if (o.get("solicitud") or "")[:10] <= filtros["hasta"]]

    contexto = {"ordenes": filtradas, "lineas": lineas}
    contexto.update(_contexto_de_filtros(filtros, ordenes, filtradas))

    return render(request, "componentes/ordenes.html", contexto)


def ordenEditarView(request, numero):

    if 'token' not in request.session:
        return redirect('login')

    if request.method == "POST":

        headers = _headers(request)

        payload = {
            "necesitada": _necesitada(request),
            "linea": request.POST.get("linea") or None,
        }

        respuesta = requests.put(f"{API}/componentes/ordenes/mod/{numero}/", json=payload, headers=headers)

        if respuesta.status_code == 200:
            messages.success(request, "Orden actualizada correctamente.")
        else:
            messages.error(request, mensaje_error(respuesta))

    return redirect('ordenes-lista')


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

    return redirect('ordenes-lista')


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

        return redirect('orden-detalle', numero=numero)

    respuesta_orden = get(f"{API}/componentes/ordenes/{numero}/", headers)

    # En un detalle no hay nada que pintar si la API falla: se regresa a la lista
    # con el motivo en lugar de una pantalla de campos en blanco.
    if fallo(respuesta_orden):
        messages.error(request, f"No se pudo cargar la orden {numero}. {mensaje_error(respuesta_orden)}")
        return redirect('ordenes-lista')

    orden = objeto(respuesta_orden)
    modelos = lista(get(f"{API}/componentes/modelos/", headers))
    modelos_por_codigo = _por_codigo(modelos)

    # Los materiales vienen con el código del modelo; en pantalla se acompaña del
    # nombre para no obligar a nadie a memorizarse el catálogo.
    for material in orden.get("detalles") or []:
        modelo = modelos_por_codigo.get(material.get("modelo")) or {}
        material["modelo_nombre"] = modelo.get("nombre")

    linea = _por_codigo(lista(get(f"{API}/lineas/", headers))).get(orden.get("linea")) or {}
    orden["linea_nombre"] = linea.get("nombre")

    # El combo de "Agregar material" sólo ofrece lo que esa línea sabe ensamblar,
    # y sale del mismo catálogo con el que el trigger rechaza lo que no toca
    # (estacion_compatibilidad_componente). Antes ofrecía los 31 modelos del
    # catálogo y la base tumbaba la mayoría, así que el error se descubría hasta
    # darle guardar.
    #
    # Si la orden todavía no tiene línea, `linea` va en None: requests no manda
    # el parámetro y la API devuelve el catálogo completo, que es lo correcto
    # porque el trigger tampoco tiene contra qué comparar.
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

    return render(
        request,
        "componentes/orden_detalle.html",
        {
            "orden": orden,
            "modelos": modelos,
            "compatibles": compatibles,
            "disponibles": disponibles,
            "lotes": lotes,
        }
    )


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

    return redirect('orden-detalle', numero=numero)


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

    return redirect('orden-detalle', numero=numero)



