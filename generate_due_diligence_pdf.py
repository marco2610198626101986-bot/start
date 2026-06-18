from pathlib import Path
from textwrap import wrap

from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas


OUTPUT_PATH = Path("/workspace/coffee_due_diligence_package.pdf")


SECTIONS = [
    (
        "1) Supplier request (Global Oil Trading PLC)",
        [
            "To: Official supplier email",
            "Subject: Due Diligence & Compliance Documents Request – Coffee Export",
            "",
            "Dear Global Oil Trading PLC Team,",
            "",
            "We are conducting mandatory supplier onboarding and compliance due diligence before any coffee purchase.",
            "",
            "Please provide clear color PDF scans (all pages) of the following documents:",
            "",
            "A) Corporate identity and legal status",
            "1) Certificate of Incorporation / Commercial Registration",
            "2) Valid Business License (current year)",
            "3) Tax Identification Number (TIN) certificate",
            "4) VAT registration (if applicable)",
            "5) Registered address confirmation and official contact details",
            "",
            "B) Coffee export authorization",
            "6) Valid Ethiopian Coffee and Tea Authority (ECTA) Coffee Exporter Competency Certificate (QR code and certificate number visible)",
            "7) Any current coffee export permit/license required for export activity",
            "8) Written confirmation that coffee export authorization is active and not suspended/revoked",
            "",
            "C) Operational and shipment evidence",
            "9) Copies of 3–5 recent coffee export shipment document sets (commercial values may be redacted):",
            "   - Commercial Invoice",
            "   - Packing List",
            "   - Bill of Lading",
            "   - Certificate of Origin",
            "   - Phytosanitary Certificate",
            "   - Quality/grade certificate (if available)",
            "10) Destination countries for these shipments",
            "11) Short summary of quality control and traceability process (1–2 pages)",
            "",
            "D) Banking and authority",
            "12) Bank account confirmation letter issued by your bank (account name must exactly match legal entity name)",
            "13) Authorized signatory list and specimen signatures",
            "14) Board resolution / Power of Attorney authorizing contract signatory",
            "",
            "E) Compliance declarations",
            "15) Signed declaration that company, directors and UBOs are not sanctioned and do not use third-party nominee accounts",
            "16) UBO disclosure and management structure",
            "",
            "Please send documents within 5 business days.",
            "",
            "Important: any future payment (if approved) will be made only to an account in the exact legal entity name and only under secure trade terms (LC/escrow).",
            "",
            "Best regards,",
            "[YOUR NAME]",
            "[YOUR TITLE]",
            "[YOUR COMPANY]",
            "[EMAIL] | [PHONE]",
        ],
    ),
    (
        "2) Request to ECTA (coffee export authorization)",
        [
            "To: Official ECTA contact",
            "Subject: Verification Request – Coffee Export Authorization (Global Oil Trading PLC)",
            "",
            "Dear Ethiopian Coffee and Tea Authority,",
            "",
            "We are a prospective international buyer conducting compliance due diligence on a potential supplier.",
            "",
            "Please confirm whether the company below is currently authorized to export coffee from Ethiopia:",
            "",
            "Company name: Global Oil Trading PLC",
            "Registration / License No.: [IF AVAILABLE]",
            "TIN: [IF AVAILABLE]",
            "Declared address: [IF AVAILABLE]",
            "",
            "Please confirm:",
            "1) Whether the coffee export authorization/certificate is valid and active",
            "2) Certificate/license number and validity period",
            "3) Scope of authorization (coffee export)",
            "4) Any current suspension, restriction, or revocation (if publicly disclosable)",
            "",
            "This request is for trade compliance and fraud prevention purposes.",
            "",
            "Kind regards,",
            "[YOUR NAME]",
            "[YOUR TITLE]",
            "[YOUR COMPANY]",
            "[EMAIL] | [PHONE]",
        ],
    ),
    (
        "3) Request to MoTRI / eTrade (company and license check)",
        [
            "To: Official Ministry of Trade / eTrade support contact",
            "Subject: Commercial Registration & Business License Verification – Global Oil Trading PLC",
            "",
            "Dear Sir/Madam,",
            "",
            "We request verification of legal registration and current business license status for the following company:",
            "",
            "Company name: Global Oil Trading PLC",
            "Registration No.: [IF AVAILABLE]",
            "TIN: [IF AVAILABLE]",
            "Declared address: [IF AVAILABLE]",
            "",
            "Please confirm:",
            "1) Exact legal name and registration status (active/inactive)",
            "2) Current business license validity period",
            "3) Licensed business activities (including export activities, if listed)",
            "4) Any public restrictions/suspensions on the license",
            "",
            "This request is made for supplier due diligence and trade compliance.",
            "",
            "Best regards,",
            "[YOUR NAME]",
            "[YOUR TITLE]",
            "[YOUR COMPANY]",
            "[EMAIL] | [PHONE]",
        ],
    ),
    (
        "4) Instruction to your bank (beneficiary verification)",
        [
            "To: Your bank relationship manager / trade finance",
            "Subject: Request for Beneficiary Bank Verification – No Release Without Confirmation",
            "",
            "Please perform bank-to-bank verification of the beneficiary account:",
            "",
            "Beneficiary legal name: Global Oil Trading PLC",
            "Beneficiary bank: [BANK NAME]",
            "Account number/IBAN: [DETAILS]",
            "SWIFT/BIC: [DETAILS]",
            "",
            "Please confirm in writing:",
            "1) Account is active",
            "2) Account holder name exactly matches legal entity name",
            "3) Account type is corporate (not personal)",
            "4) No mismatch between contract party and beneficiary account holder",
            "",
            "Instruction: no payment release until written verification is received.",
        ],
    ),
    (
        "5) Reference request to supplier",
        [
            "To: Supplier contact",
            "Subject: Buyer References Request – Coffee Export Track Record",
            "",
            "Dear [Supplier Contact Name],",
            "",
            "For final onboarding approval, please provide at least 3 international buyer references from the last 12–18 months:",
            "",
            "1) Company name",
            "2) Contact person (name, title, corporate email)",
            "3) Country",
            "4) Approximate shipment period and product type",
            "5) Confirmation that we may contact them for reference",
            "",
            "Thank you.",
        ],
    ),
    (
        "6) Request to inspection company (SGS/BV/Intertek)",
        [
            "To: Inspection company",
            "Subject: Request for Pre-Shipment Inspection & Document Verification – Ethiopian Coffee",
            "",
            "Dear [Inspection Company],",
            "",
            "Please provide quotation and scope for independent pre-shipment inspection for coffee export from Ethiopia.",
            "",
            "Required scope:",
            "1) Physical cargo inspection (quantity/condition)",
            "2) Container/seal verification",
            "3) Document consistency check (invoice, packing list, B/L draft, CoO, phytosanitary, quality docs)",
            "4) Photo evidence report",
            "5) Turnaround time and total fee",
            "",
            "Shipment reference: [LOT / CONTRACT REF]",
            "Exporter: Global Oil Trading PLC",
            "Origin: Ethiopia",
            "Destination: [COUNTRY/PORT]",
            "",
            "Best regards,",
            "[YOUR NAME]",
            "[COMPANY]",
        ],
    ),
    (
        "7) Internal STOP checklist (go / no-go)",
        [
            "NO-GO if at least one of the following is true:",
            "",
            "1) ECTA does not confirm active coffee export authorization.",
            "2) Legal entity name in contract does not match beneficiary bank account holder.",
            "3) Supplier refuses to provide 3–5 recent export document sets.",
            "4) Supplier insists on prepayment without LC/escrow.",
            "5) Material mismatches across TIN/registration number/address/signatories.",
        ],
    ),
]


def draw_lines(c: canvas.Canvas, lines: list[str], x: int, y: int, max_width_chars: int) -> int:
    text_line_height = 14
    for line in lines:
        wrapped = wrap(line, width=max_width_chars) if line else [""]
        for part in wrapped:
            if y < 60:
                c.showPage()
                c.setFont("Helvetica", 11)
                y = 790
            c.drawString(x, y, part)
            y -= text_line_height
    return y


def build_pdf() -> None:
    c = canvas.Canvas(str(OUTPUT_PATH), pagesize=A4)
    c.setTitle("Coffee Due Diligence Request Package")
    c.setAuthor("Prepared by assistant")

    y = 800
    c.setFont("Helvetica-Bold", 16)
    c.drawString(50, y, "Coffee Due Diligence Request Package")
    y -= 24
    c.setFont("Helvetica", 11)
    y = draw_lines(
        c,
        [
            "Prepared for compliance verification of Global Oil Trading PLC (Ethiopia).",
            "Use placeholders in square brackets before sending.",
            "",
        ],
        50,
        y,
        max_width_chars=95,
    )

    for title, body_lines in SECTIONS:
        if y < 120:
            c.showPage()
            y = 800
        c.setFont("Helvetica-Bold", 13)
        c.drawString(50, y, title)
        y -= 20
        c.setFont("Helvetica", 11)
        y = draw_lines(c, body_lines + [""], 50, y, max_width_chars=95)

    c.save()


if __name__ == "__main__":
    build_pdf()
    print(f"Created: {OUTPUT_PATH}")
