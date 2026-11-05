#!/usr/bin/env bash
# Genera informe_tp7.pdf a partir de informe/informe_tp7.html con Chrome sin interfaz
# y verifica que no supere las 5 páginas que permite la consigna.
# Uso, desde la raíz del repo:  bash informe/generar_pdf.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"
HTML="$(cygpath -m "$DIR/informe/informe_tp7.html")"
PDF="$DIR/informe_tp7.pdf"
MAX_PAGINAS=5

"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="$(cygpath -w "$PDF")" "file:///$HTML" 2>/dev/null

paginas=$(python -I -c "import sys, pypdf; print(len(pypdf.PdfReader(sys.argv[1]).pages))" "$(cygpath -w "$PDF")")
echo "informe_tp7.pdf: $paginas página(s)"
[ "$paginas" -le "$MAX_PAGINAS" ] || { echo "ERROR: el informe supera las $MAX_PAGINAS páginas" >&2; exit 1; }
