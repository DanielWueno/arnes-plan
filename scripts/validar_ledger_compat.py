# -*- coding: utf-8 -*-
"""Puente de importación para `validar-ledger.py`.

El fichero se llama con guiones porque es un ejecutable de línea de comandos, y
un guión no es un identificador válido en Python: `import validar-ledger` no
existe. Este módulo lo carga por ruta y reexporta lo que otros necesitan, para
que la lista de campos conocidos tenga UN solo dueño.
"""
import importlib.util
import os

_ruta = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'validar-ledger.py')
_spec = importlib.util.spec_from_file_location('_validar_ledger', _ruta)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

ESQUEMA_SOPORTADO = _mod.ESQUEMA_SOPORTADO
CONOCIDAS = _mod.CONOCIDAS
CAMPOS_ITEM = _mod.CAMPOS_ITEM
