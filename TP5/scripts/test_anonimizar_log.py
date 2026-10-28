"""Pruebas de anonimizar_log.py. Uso: python -I TP5/scripts/test_anonimizar_log.py"""
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'anonimizar_log.py')

PREFIJO_APP = '2026-10-28 15:24:28.193 -03 [27520] sesion=aaa.1 user=app_web db=foodstore_tp5 app=psql client=::1 '
PREFIJO_DBA = '2026-10-28 15:24:28.148 -03 [18652] sesion=bbb.2 user=postgres db=foodstore_tp5 app=psql client=::1 '


def anonimizar(lineas, mapa='cuenta7@foodstore.test,usuario7@ejemplo.test\n'):
    with tempfile.TemporaryDirectory() as d:
        log, csv = os.path.join(d, 'log.txt'), os.path.join(d, 'mapa.csv')
        with open(log, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lineas))
        with open(csv, 'w', encoding='utf-8') as f:
            f.write(mapa)
        r = subprocess.run([sys.executable, '-I', SCRIPT, log, csv],
                           capture_output=True, text=True, encoding='utf-8', check=True)
        return r.stdout


class AnonimizarLog(unittest.TestCase):

    def test_ruta_windows_con_cualquier_carpeta_de_datos(self):
        salida = anonimizar([PREFIJO_APP + 'LOG:  connection authenticated: identity="app_web" '
                             'method=scram-sha-256 (C:/Users/Ana Perez/datos pg/cluster_dev/pg_hba.conf:123)'])
        self.assertNotIn('Ana Perez', salida)
        self.assertIn('(<PGDATA>/pg_hba.conf:123)', salida)

    def test_ruta_unix(self):
        salida = anonimizar([PREFIJO_APP + 'DETAIL:  Connection matched file '
                             '"/home/jperez/pg/main/pg_hba.conf" line 98: "host all all ::1/128 scram-sha-256"'])
        self.assertNotIn('jperez', salida)
        self.assertIn('"<PGDATA>/pg_hba.conf" line 98', salida)

    def test_mails_del_mapa_y_desconocidos(self):
        salida = anonimizar([PREFIJO_APP + 'WARNING:  fn_autenticar: intento fallido mail=cuenta7@foodstore.test',
                             PREFIJO_APP + 'WARNING:  fn_autenticar: intento fallido mail=intruso@otro.com'])
        self.assertIn('mail=usuario7@ejemplo.test', salida)
        self.assertIn('mail=desconocido1@ejemplo.test', salida)
        self.assertNotIn('foodstore.test', salida)
        self.assertNotIn('intruso', salida)

    def test_quita_sesiones_del_dba_con_sus_continuaciones(self):
        salida = anonimizar([PREFIJO_DBA + 'LOG:  TP5-C inicio 20261028T152428',
                             PREFIJO_DBA + 'STATEMENT:  DO $$',
                             '\tBEGIN RAISE LOG \'TP5-C fin\'; END $$;',
                             PREFIJO_APP + 'ERROR:  permission denied for table usuario'])
        self.assertNotIn('TP5-C', salida)
        self.assertNotIn('user=postgres', salida)
        self.assertIn('permission denied for table usuario', salida)


if __name__ == '__main__':
    unittest.main()
