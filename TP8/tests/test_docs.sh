#!/usr/bin/env bash
# test_docs: valida la documentacion de especificacion exportada en docs/kiro/,
# bitacora de IA, DUIA y (opcionalmente) extension del informe PDF.
export PATH="$PATH:/d/DevTools/miniconda3/Library/bin"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

falla() { echo "test_docs: FALLA - $1"; exit 1; }

REQ="$RAIZ/docs/kiro/requirements.md"
DES="$RAIZ/docs/kiro/design.md"
TSK="$RAIZ/docs/kiro/tasks.md"
BIT="$RAIZ/docs/bitacora_ia.md"
DUIA="$RAIZ/docs/DUIA.md"
PDF="$RAIZ/docs/informe.pdf"

# 1. Existencia de archivos de Kiro
[ -f "$REQ" ] || falla "docs/kiro/requirements.md no existe"
[ -f "$DES" ] || falla "docs/kiro/design.md no existe"
[ -f "$TSK" ] || falla "docs/kiro/tasks.md no existe"

# 2. Formato EARS en requirements.md: al menos 4 requisitos con WHEN y THE SYSTEM SHALL,
# y cada uno con "Se prueba con: C[1-7]"
n_when=$(grep -c "WHEN " "$REQ" || true)
n_shall=$(grep -c "THE SYSTEM SHALL" "$REQ" || true)
n_prueba=$(grep -E -c "Se prueba con: C[1-7]" "$REQ" || true)

[ "$n_when" -ge 4 ] || falla "requirements.md tiene menos de 4 clausulas WHEN (tiene $n_when)"
[ "$n_shall" -ge 4 ] || falla "requirements.md tiene menos de 4 clausulas THE SYSTEM SHALL (tiene $n_shall)"
[ "$n_prueba" -ge 4 ] || falla "requirements.md tiene menos de 4 clausulas 'Se prueba con: C' (tiene $n_prueba)"

# 3. Bitacora de IA: al menos 3 entradas y al menos un descarte
[ -f "$BIT" ] || falla "docs/bitacora_ia.md no existe"
n_entradas=$(grep -E -c "^\| [0-9]+ \|" "$BIT" || true)
[ "$n_entradas" -ge 3 ] || falla "docs/bitacora_ia.md tiene menos de 3 entradas (tiene $n_entradas)"
grep -i -q "descart" "$BIT" || falla "docs/bitacora_ia.md no contiene ningun hallazgo o propuesta descartada"

# 4. DUIA: declara Claude Code, OpenSpec y que no se uso Kiro/OpenCode
[ -f "$DUIA" ] || falla "docs/DUIA.md no existe"
grep -i -q "Claude Code" "$DUIA" || falla "DUIA.md no menciona Claude Code"
grep -i -q "OpenSpec" "$DUIA" || falla "DUIA.md no menciona OpenSpec"
grep -i -q "Kiro" "$DUIA" && grep -i -q "OpenCode" "$DUIA" || falla "DUIA.md no declara el desvio respecto de Kiro/OpenCode"

# 5. Extension del informe PDF (si existe)
if [ -f "$PDF" ]; then
  PDF_WIN="$(cygpath -m "$PDF")"
  python -c "
import pypdf, sys
reader = pypdf.PdfReader('$PDF_WIN')
n = len(reader.pages)
print(f'informe.pdf: {n} pagina(s)')
if n > 6:
    sys.exit(1)
" || falla "el informe PDF supera el maximo de 6 paginas"
fi

echo "test_docs: OK"
