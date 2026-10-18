#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Genera TP4/informe_tp4.pdf a partir de TP4/informe_tp4.md.

Referencia: TP3/gen_pdf.py (misma libreria, fpdf2). A diferencia de aquel, que arma el contenido
a mano con fuentes basicas, este script convierte el Markdown del informe (markdown-it-py -> HTML ->
FPDF.write_html) para que el PDF no se desincronice del .md. Usa fuentes TrueType del sistema
(Segoe UI y Consolas de Windows) porque el informe lleva caracteres fuera de Latin-1 (flechas, "≥", "≈").
Unico reemplazo: "∪" (U+222A) no existe en esas fuentes y se escribe como "U".

Dependencias: fpdf2 y markdown-it-py (ya instaladas en este entorno). Uso:  python TP4/gen_pdf.py
"""
import os
import re
import sys

from fpdf import FPDF
from fpdf.fonts import TextStyle
from markdown_it import MarkdownIt

AQUI = os.path.dirname(os.path.abspath(__file__))
ENTRADA = os.path.join(AQUI, "informe_tp4.md")
SALIDA = os.path.join(AQUI, "informe_tp4.pdf")
FUENTES = os.environ.get("WINDIR", "C:/Windows") + "/Fonts"

REEMPLAZOS = {"∪": "U"}


class Informe(FPDF):
    def footer(self):
        self.set_y(-14)
        self.set_font("Texto", "", 8)
        self.set_text_color(120, 120, 120)
        self.cell(0, 8, f"TP4 - FNBC y desnormalizacion controlada - Food Store | Pag. {self.page_no()}", align="C")


def preparar_html(md_texto):
    for k, v in REEMPLAZOS.items():
        md_texto = md_texto.replace(k, v)
    md = MarkdownIt("commonmark").enable("table")
    html = md.render(md_texto)
    # write_html no maneja bien <pre><code>: se deja solo <pre> con el texto escapado.
    html = re.sub(r"<pre><code[^>]*>", "<pre>", html)
    html = html.replace("</code></pre>", "</pre>")
    # <code> en linea -> negrita monoespaciada no esta soportada: se usa <font face="Codigo">.
    html = html.replace("<code>", '<font face="Codigo">').replace("</code>", "</font>")
    html = html.replace("<strong>", "<b>").replace("</strong>", "</b>").replace("<em>", "<i>").replace("</em>", "</i>")
    # write_html no admite etiquetas anidadas dentro de <td>/<th>: se deja solo el texto de la celda.
    html = re.sub(r"(<t[dh][^>]*>)(.*?)(</t[dh]>)",
                  lambda m: m.group(1) + re.sub(r"</?(font|b|i|a|code)[^>]*>", "", m.group(2)) + m.group(3),
                  html, flags=re.S)
    # Las tablas necesitan width explicito para ocupar todo el ancho.
    html = html.replace("<table>", '<table width="100%" border="1">')
    # Listas anidadas / parrafos dentro de <li>: simplificar.
    html = re.sub(r"<li>\s*<p>", "<li>", html)
    html = re.sub(r"</p>\s*</li>", "</li>", html)
    return html


def main():
    with open(ENTRADA, encoding="utf-8") as f:
        texto = f.read()
    html = preparar_html(texto)

    pdf = Informe(orientation="P", unit="mm", format="A4")
    pdf.set_margins(16, 16, 16)
    pdf.set_auto_page_break(auto=True, margin=18)
    pdf.add_font("Texto", "", f"{FUENTES}/segoeui.ttf")
    pdf.add_font("Texto", "B", f"{FUENTES}/segoeuib.ttf")
    pdf.add_font("Texto", "I", f"{FUENTES}/segoeuii.ttf")
    pdf.add_font("Texto", "BI", f"{FUENTES}/segoeuiz.ttf")
    pdf.add_font("Codigo", "", f"{FUENTES}/consola.ttf")
    pdf.add_font("Codigo", "B", f"{FUENTES}/consolab.ttf")
    pdf.add_font("Codigo", "I", f"{FUENTES}/consolai.ttf")
    pdf.add_font("Codigo", "BI", f"{FUENTES}/consolaz.ttf")
    pdf.set_title("Informe TP4 - FNBC y desnormalizacion controlada (Food Store)")
    pdf.set_author("Matias Limina")
    pdf.add_page()
    pdf.set_font("Texto", "", 9)
    pdf.write_html(
        html,
        tag_styles={
            "h1": TextStyle(font_family="Texto", font_style="B", font_size_pt=15, color=(22, 68, 128), t_margin=4, b_margin=2),
            "h2": TextStyle(font_family="Texto", font_style="B", font_size_pt=12, color=(22, 68, 128), t_margin=3, b_margin=1),
            "h3": TextStyle(font_family="Texto", font_style="B", font_size_pt=10, color=(40, 40, 40), t_margin=2, b_margin=1),
            "pre": TextStyle(font_family="Codigo", font_size_pt=7, color=(40, 40, 40), t_margin=1, b_margin=2),
        },
        table_line_separators=True,
    )
    pdf.output(SALIDA)
    print(f"OK: {SALIDA} ({pdf.page_no()} paginas)")


if __name__ == "__main__":
    sys.exit(main())
