

import re
from datetime import date, datetime, time

from django import template

register = template.Library()

FORMATO_FECHA = '%d/%m/%Y'
FORMATO_HORA = '%H:%M:%S'

# Formas en las que puede llegar una fecha desde la API.
PATRONES_FECHA = ('%Y-%m-%d', '%d-%m-%Y', '%Y/%m/%d', '%d/%m/%Y')

# Idem para la hora. DRF manda HH:MM:SS, pero un <input type="time"> manda HH:MM
# y los microsegundos aparecen cuando el valor viene de un DateTimeField.
PATRONES_HORA = ('%H:%M:%S.%f', '%H:%M:%S', '%H:%M')

# La zona horaria pegada al final de un DateTimeField con USE_TZ:
# '2026-07-21T07:30:00-07:00' deja '07:30:00-07:00' al recortar la fecha, y
# ninguno de los patrones de arriba se la come.
ZONA_HORARIA = re.compile(r'(?:Z|[+-]\d{2}:?\d{2})$')


def _a_fecha(valor):
    """Convierte a date lo que se pueda; None si no se puede."""
    if isinstance(valor, datetime):
        return valor.date()
    if isinstance(valor, date):
        return valor

    texto = str(valor).strip()
    if not texto:
        return None

    # Un datetime completo ("2026-07-21T08:00:00") trae la fecha por delante.
    texto = texto.replace('T', ' ').split(' ')[0]

    for patron in PATRONES_FECHA:
        try:
            return datetime.strptime(texto, patron).date()
        except ValueError:
            continue
    return None


def _a_hora(valor):
    """Convierte a time lo que se pueda; None si no se puede."""
    if isinstance(valor, datetime):
        return valor.time()
    if isinstance(valor, time):
        return valor

    texto = str(valor).strip()
    if not texto:
        return None

    # Si viene un datetime completo, la hora va después del separador.
    if 'T' in texto or ' ' in texto:
        texto = texto.replace('T', ' ').split(' ')[-1]

    # Sin esto, un '07:30:00-07:00' no casaba con ningún patrón y la hora salía
    # en pantalla como el datetime crudo completo.
    texto = ZONA_HORARIA.sub('', texto)

    for patron in PATRONES_HORA:
        try:
            return datetime.strptime(texto, patron).time()
        except ValueError:
            continue
    return None


@register.filter
def fecha(valor):
    """Fecha en DD/MM/AAAA.

    >>> fecha('2026-07-21')
    '21/07/2026'
    """
    if valor in (None, ''):
        return ''
    convertida = _a_fecha(valor)
    return convertida.strftime(FORMATO_FECHA) if convertida else str(valor)


@register.filter
def hora(valor):
    """Hora en HH:MM:SS. Completa los segundos si vienen recortados.

    >>> hora('08:00')
    '08:00:00'
    """
    if valor in (None, ''):
        return ''
    convertida = _a_hora(valor)
    return convertida.strftime(FORMATO_HORA) if convertida else str(valor)


@register.filter
def fecha_hora(valor, hora_valor=None):
    """Fecha y hora juntas en DD/MM/AAAA HH:MM:SS.

    Se usa con la hora como argumento, porque la API las manda en dos campos:

        {{ r.fecha_inicio|fecha_hora:r.hora_inicio }}

    Si sólo hay fecha, devuelve la fecha sola en vez de inventar 00:00:00: no es
    lo mismo "no se registró la hora" que "pasó a medianoche".

    >>> fecha_hora('2026-07-21', '08:00:00')
    '21/07/2026 08:00:00'
    """
    if valor in (None, '') and hora_valor in (None, ''):
        return ''

    partes = [p for p in (fecha(valor), hora(hora_valor)) if p]
    return ' '.join(partes)



@register.filter
def duracion(minutos):
    """Minutos en algo que se lea de un vistazo: '35 min', '2 h 10 min', '3 d 4 h'.

    Un 0 es un dato bueno —abrió y cerró en el mismo minuto—, así que se escribe
    como '0 min' y no como vacío; el vacío se reserva para cuando de plano no hay
    dato (None).

    >>> duracion(130)
    '2 h 10 min'
    """
    if minutos in (None, ''):
        return ''

    try:
        total = int(minutos)
    except (TypeError, ValueError):
        return str(minutos)

    if total < 60:
        return f'{total} min'

    horas, resto = divmod(total, 60)
    if horas < 24:
        return f'{horas} h {resto} min' if resto else f'{horas} h'

    dias, horas = divmod(horas, 24)
    return f'{dias} d {horas} h' if horas else f'{dias} d'


@register.filter
def rango(total):
    """Genera un rango de 1 a total, para pintar botones de paginación.

    >>> {% for num in total_pages|rango %}
    """
    try:
        return range(1, int(total) + 1)
    except (TypeError, ValueError):
        return range(0)
