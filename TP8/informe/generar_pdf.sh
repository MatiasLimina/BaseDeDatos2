#!/usr/bin/env bash
# generar_pdf.sh: compila informe/informe.html a docs/informe.pdf utilizando
# un navegador headless (Google Chrome o Microsoft Edge) y valida la extension
# maxima permitida (<= 6 paginas) mediante pypdf.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
HTML="$RAIZ/informe/informe.html"
PDF="$RAIZ/docs/informe.pdf"

[ -f "$HTML" ] || { echo "ERROR: no se encontro $HTML"; exit 1; }
mkdir -p "$RAIZ/docs"

# 1. Localizar binario headless (Chrome o Edge)
BROWSER=""
for candidate in \
  "/c/Program Files/Google/Chrome/Application/chrome.exe" \
  "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
  "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
  "/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
  "$(which chrome.exe 2>/dev/null || true)" \
  "$(which msedge.exe 2>/dev/null || true)"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    BROWSER="$candidate"
    break
  fi
done

[ -n "$BROWSER" ] || { echo "ERROR: no se encontro Google Chrome ni Microsoft Edge en el sistema"; exit 1; }

echo "generar_pdf: usando navegador $BROWSER"

# 2. Rutas compatibles con Windows
HTML_WIN="$(cygpath -m "$HTML")"
PDF_WIN="$(cygpath -m "$PDF")"

# 3. Compilacion Headless a PDF
"$BROWSER" --headless=new --disable-gpu --print-to-pdf="$PDF_WIN" --no-pdf-header-footer "file:///$HTML_WIN" 2>/dev/null || true

[ -f "$PDF" ] || { echo "ERROR: la generacion de $PDF fallo"; exit 1; }

# 4. Validacion de extension con pypdf
export PATH="$PATH:/d/DevTools/miniconda3/Library/bin"
PAGINAS=$(python -c "
import pypdf, sys
try:
    reader = pypdf.PdfReader('$PDF_WIN')
    n = len(reader.pages)
    print(n)
    if n > 6:
        sys.exit(2)
    if n < 1:
        sys.exit(3)
except Exception as e:
    print(f'Error al leer PDF: {e}', file=sys.stderr)
    sys.exit(1)
")

echo "generar_pdf: OK - PDF generado en $PDF ($PAGINAS paginas, maximo permitido: 6)"
