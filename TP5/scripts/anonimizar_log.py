"""Anonimiza un fragmento de log de PostgreSQL antes de entregárselo a una IA.

Parte C.3 del TP Unidad 5. Uso:

    python -I anonimizar_log.py <log_crudo> <mapa_mails.csv> > <log_anonimizado>

<mapa_mails.csv> tiene una línea "mail_real,mail_sintetico" por cuenta y se
genera desde la base con el mismo criterio que usuario_anon (Clase 2):

    psql -At -F, -c "SELECT mail, 'usuario' || id || '@ejemplo.test' FROM usuario"

Qué hace:
  1. Quita las sesiones del DBA (user=postgres): son el andamiaje del
     simulacro (marcadores y verificación), no parte del incidente.
  2. Reemplaza cada mail del mapa por su valor sintético; un mail que no está
     en el mapa pasa a desconocidoN@ejemplo.test.
  3. Reemplaza las rutas del sistema de archivos del servidor (exponen el
     usuario del sistema operativo) por <PGDATA>.
En stderr deja un resumen de lo reemplazado; no imprime ningún valor real.
"""
import csv
import re
import sys

SESION = re.compile(r' sesion=(\S+) ')
USUARIO_DBA = re.compile(r' user=postgres ')
MAIL = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
# Directorio de cualquier ruta absoluta (Windows o Unix, con espacios) que
# lleve a un archivo de configuración del servidor, sea cual sea el nombre
# de la carpeta de datos: "C:/Users/<usuario>/.../pg_hba.conf" -> "<PGDATA>/pg_hba.conf".
RUTA = re.compile(r'(?:[A-Za-z]:)?/[^"()\n]*?/(?=(?:pg_hba|pg_ident|postgresql(?:\.auto)?)\.conf)')


def main(ruta_log, ruta_mapa):
    with open(ruta_mapa, encoding='utf-8') as f:
        mapa = {real.lower(): sintetico for real, sintetico in csv.reader(f)}
    with open(ruta_log, encoding='utf-8') as f:
        lineas = f.read().splitlines()

    sesiones_dba = {SESION.search(l).group(1) for l in lineas
                    if USUARIO_DBA.search(l) and SESION.search(l)}

    desconocidos = {}
    cuenta = {'lineas_dba': 0, 'mails': 0, 'rutas': 0}

    def reemplazar_mail(m):
        real = m.group(0).lower()
        cuenta['mails'] += 1
        if real in mapa:
            return mapa[real]
        if real not in desconocidos:
            desconocidos[real] = f'desconocido{len(desconocidos) + 1}@ejemplo.test'
        return desconocidos[real]

    salida = []
    sesion_actual = None
    for linea in lineas:
        s = SESION.search(linea)
        if s:
            sesion_actual = s.group(1)
        # Las líneas de continuación (sin prefijo) heredan la sesión anterior.
        if sesion_actual in sesiones_dba:
            cuenta['lineas_dba'] += 1
            continue
        linea, n = RUTA.subn('<PGDATA>/', linea)
        cuenta['rutas'] += n
        salida.append(MAIL.sub(reemplazar_mail, linea))

    sys.stdout.reconfigure(encoding='utf-8', newline='\n')
    print('\n'.join(salida))
    print(f"anonimizar_log: {cuenta['lineas_dba']} líneas del DBA quitadas, "
          f"{cuenta['mails']} mails y {cuenta['rutas']} rutas reemplazados, "
          f"{len(desconocidos)} mails fuera del mapa", file=sys.stderr)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
