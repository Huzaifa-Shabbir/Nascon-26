"""Server-side PDF receipt generation (ReportLab / ADR-7)."""
from __future__ import annotations

import base64
import io

from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas


def format_pkr(total_minor: int) -> str:
    """Major units, two decimals, no thousands separator — e.g. PKR 4500.00."""
    major = total_minor // 100
    minor = abs(total_minor) % 100
    return f"PKR {major}.{minor:02d}"


def build_receipt_pdf(*, order_id: str, total_minor: int, customer_id: str) -> bytes:
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    c.setTitle(f"Receipt {order_id}")
    y = 800
    c.setFont("Helvetica-Bold", 16)
    c.drawString(72, y, "NaSCon Store Receipt")
    y -= 36
    c.setFont("Helvetica", 12)
    c.drawString(72, y, f"Order ID: {order_id}")
    y -= 20
    c.drawString(72, y, f"Customer: {customer_id}")
    y -= 20
    c.drawString(72, y, f"Total: {format_pkr(total_minor)}")
    c.showPage()
    c.save()
    data = buf.getvalue()
    if not data.startswith(b"%PDF"):
        raise RuntimeError("PDF generator did not emit a PDF header")
    return data


def pdf_base64(**kwargs) -> str:
    return base64.b64encode(build_receipt_pdf(**kwargs)).decode("ascii")
