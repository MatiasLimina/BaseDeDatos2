#!/usr/bin/env bash
# Genera TP6/informe_u6.pdf a partir de informe/informe_u6.html con Chrome sin interfaz
# y verifica que ocupe una sola página (la consigna pide "una página como máximo").
# Uso, desde TP6/:  bash informe/generar_pdf.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"
HTML="$(cygpath -m "$DIR/informe/informe_u6.html")"
PDF="$DIR/informe_u6.pdf"

"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="$(cygpath -w "$PDF")" "file:///$HTML" 2>/dev/null

paginas=$(python -I -c "import sys, pypdf; print(len(pypdf.PdfReader(sys.argv[1]).pages))" "$(cygpath -w "$PDF")")
echo "informe_u6.pdf: $paginas página(s)"
[ "$paginas" -eq 1 ] || { echo "ERROR: el informe debe ocupar una página" >&2; exit 1; }
