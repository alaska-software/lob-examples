# E-Invoice Factory for Xbase++ — Usage Guide
<small>Rev. 1.1 Nov.2026</small>

`alaska-software.e-invoice-factory.dll` builds and reads **EN 16931** e-invoices —
**XRechnung 3.0** or **ZUGFeRD 2.x / Factur-X** (CII syntax) — from/to an in-memory invoice
model. No PDF, no DBF tables, no network calls: you build the model from whatever data you
already have (plain `DataObject`s, DBF rows, anything), the DLL calculates the tax breakdown
and totals, checks the result against the EN 16931/XRechnung rule catalogue, and serializes
it. It is validated against the official CII D16B XSD, the CEN EN 16931 Schematron and the
KoSIT XRechnung Schematron — see the **Appendix** at the end of this guide for the 
authoritative legal/standards sources behind every rule this module enforces.

This guide covers the three things a Line-of-Business developer actually does with the
module: **create** an XRechnung, build the model **either as objects or as plain DTOs**, and
**validate a document loaded from disk**. For the full method-by-method reference (every
`setXXX()`/`getXXX()`, its BT/BG number, what it defaults to, what rule checks it), read the
reference at https://doc.alaska-software.com group "eInvoice".

---

## 1. Creating an XRechnung

### 1.1 The five steps

1. Build the **seller** and **buyer** (`EinvoiceParty` — name, VAT ID, address, ...).
2. Hand both to **`EinvFactory():createInvoice()`** — it looks at the seller's and buyer's
   country alone and returns the right `AbstractEinvoice` subclass already populated with
   both parties: `DomesticEinvoice` (same country), `IntraEuEinvoice` (another EU member
   state) or `ExportEinvoice` (outside the EU). A non-EU seller gets a `ManualEinvoice`
   instead — see §1.4.
3. Add **line items** (`:addLineItem()`), and anything else the invoice needs: payment means
   (`:setPaymentMeans()`), payment terms (`:setPaymentTerms()`), delivery date
   (`:setDeliveryDate()`), allowances/charges, notes, ...
4. Call **`:validate()`**. It never raises — it returns a `DataObject{Valid, Errors,
   Warnings, Model}`, each error/warning carrying its own EN 16931/XRechnung rule id, so you
   can print or log every problem at once instead of stopping at the first.
5. Once `:Valid`, call **`:toXRechnung()`** (or `:toZugferd( "EN16931" )` for the hybrid
   format) to get the XML string. Both run `:validate()` again internally plus their own
   extra, format-specific checks (XRechnung's German CIUS rules `BR-DE-*`, the PEPPOL rules
   it adopted) and **raise** via `Exception():raisePlainText()` if any error remains — call
   `:validate()` yourself first (step 4) to decide whether it is even worth attempting.

### 1.2 Minimal example

```xbase
LOCAL oSeller, oBuyer, oInvoice, oResult, cXml, nI

oSeller := EinvoiceParty():new()
oSeller:setName( "Northwind Inc., Germany" )
oSeller:setVatId( "DE123456789" )
oSeller:setAddress( EinvoiceAddress():new():setLine1( "Alexanderplatz 7" ):setPostcode( "10178" ):setCity( "Berlin" ):setCountryCode( "DE" ) )
oSeller:setContact( "Accounting", "+49 30 1234567-0", "invoicing@northwind-inc.example" )
oSeller:setElectronicAddress( "invoicing@northwind-inc.example" )   // BT-34, PEPPOL-EN16931-R020

oBuyer := EinvoiceParty():new()
oBuyer:setName( "Example GmbH" )
oBuyer:setAddress( EinvoiceAddress():new():setLine1( "Hauptstrasse 5" ):setPostcode( "10115" ):setCity( "Berlin" ):setCountryCode( "DE" ) )
oBuyer:setElectronicAddress( "ap@example.example" )                  // BT-49, PEPPOL-EN16931-R010

oInvoice := EinvFactory():createInvoice( oSeller, oBuyer, "INV-2026-0001", Date() )   // -> DomesticEinvoice here
oInvoice:setBuyerReference( "PO-4711" )                               // BT-10, required by BR-DE-15
oInvoice:setDeliveryDate( Date() )
oInvoice:setPaymentMeans( EinvoicePaymentMeans():new():setIban( "DE89370400440532013000" ):setAccountName( "Northwind Inc." ) )
oInvoice:setPaymentTerms( EinvoicePaymentTerms():new():setDueDate( Date() + 14 ) )
oInvoice:addLineItem( EinvoiceLineItem():new():setName( "Widget" ):setQuantity( 2 ):setPrice( 9.50 ):setVatRate( 19 ) )

oResult := oInvoice:validate()
IF !oResult:Valid
   FOR nI := 1 TO Len( oResult:Errors )
      ? "[" + oResult:Errors[nI]:Rule + "] " + oResult:Errors[nI]:Message
   NEXT
ELSE
   cXml := oInvoice:toXRechnung()
   // write cXml wherever it needs to go (FCreate()/FWrite()/FClose(), as below)
ENDIF
```

Only the seller's and buyer's `CountryCode` are required for `EinvFactory()` to pick the
scenario; everything else is ordinary invoice content. `EinvoiceParty`/`EinvoiceAddress`/
`EinvoiceLineItem`/`EinvoicePaymentMeans`/`EinvoicePaymentTerms`/`EinvoiceAllowanceCharge`
all follow the same pattern: construct with `():new()`, then chain `setXXX()` calls — every
setter returns `self`. Amounts/quantities/rates accept a plain `Numeric` or `Character`
(`"19.99"`, `"19,99"`) and are converted to an exact `EinvoiceDecimal` internally; see
`einvoice-decimal.prg` if you need to compute with one directly (e.g. to read
`oInvoice:toModel():Totals:GrandTotal` back out).

### 1.3 The worked, data-driven example: `examples/create-invoices.prg`

For a complete, real example that reads actual data (Northwind demo order/customer/line-item
DBF tables) and produces both XRechnung and ZUGFeRD files for three different tax scenarios
in one run, read `examples/create-invoices.prg` (and its own `examples/readme.md`). It is
deliberately structured as the shape to copy into your own integration:

- `CreateEInvoice( oSeller, cInvoiceId, cDataPath )` — the one function with a single
  concern: read one order from your tables, build the buyer `EinvoiceParty`/
  `EinvoiceAddress`/line items with `setXXX()`, call `EinvFactory():createInvoice()`, and
  return the `AbstractEinvoice`. No validation, no XML, no file I/O — this is the part you
  adapt, swapping the DBF-specific lines for your own tables.
- `Main()` — calls `:validate()` directly, prints every error/warning with its rule id, and
  only calls `SaveEInvoice()` once `:Valid`.
- `SaveEInvoice()` — calls `:toXRechnung()`/`:toZugferd()`, each guarded in its own
  `BEGIN SEQUENCE/RECOVER`, since both raise once a validation error remains.

Three demo invoices exercise the three automatic scenarios end to end (domestic 19% VAT,
intra-EU VAT-exempt, export VAT-exempt) — see the table in `examples/readme.md` for exactly
which Northwind invoice id maps to which scenario, and run it (`create-invoices.exe`) to see
real XRechnung/ZUGFeRD output on disk.

### 1.4 When you already know the scenario, or it doesn't fit the automatic three

`EinvFactory():createInvoice()` is the normal entry point, but you can instantiate
`DomesticEinvoice():new(...)` / `IntraEuEinvoice():new(...)` / `ExportEinvoice():new(...)`
directly when the scenario is already known for certain (skipping the country-based
decision), and **`ManualEinvoice`** is the one scenario that applies no automatic VAT logic
at all — every line states its own `vatCategory` (and `vatRate` for `"S"`) via
`EinvoiceLineItem:setVatCategory()`/`:setVatRate()`. Use it for a non-EU seller (automatic
fallback of `EinvFactory():createInvoice()`), a special VAT scheme, or whenever the three
automatic scenarios do not apply — `EinvFactory():createManualInvoice()` is the explicit way
to ask for it directly. See §1 of the Appendix below for the full scenario-to-VAT-category
decision table.

---

## 2. Building the model as DTOs instead of `setXXX()`

Every model class accepts a **plain `DataObject`** with the same member names as an
alternative to the `setXXX()` builder chain — `EinvoiceParty():new( oDataObject )` instead of
`EinvoiceParty():new():setName(...):setAddress(...)`. Both paths normalize identically (VAT
ID cleaned up and upper-cased, country code upper-cased, text converted to UTF-8, ...),
because the DTO constructor itself just unpacks the `DataObject` and calls the matching
`setXXX()` for each member — nothing is skipped or treated differently. `EinvFactory()` and
every `:addRecipient()`/`:addLineItem()`/`:setPaymentMeans()`/etc. normalize their argument
through `EinvoiceXxx:from()`, so a plain `DataObject` works everywhere an `EinvoiceXxx`
object is expected — you never have to construct the class yourself if you would rather just
fill in a `DataObject`:

```xbase
LOCAL oSellerAddr := DataObject():new()
oSellerAddr:Line1       := "Alexanderplatz 7"
oSellerAddr:Postcode    := "10178"
oSellerAddr:City        := "Berlin"
oSellerAddr:CountryCode := "DE"

LOCAL oSeller := DataObject():new()
oSeller:Name              := "Northwind Inc., Germany"
oSeller:VatId             := "DE123456789"
oSeller:Address           := oSellerAddr
oSeller:ElectronicAddress := "invoicing@northwind-inc.example"

LOCAL oInvoice := EinvFactory():createInvoice( oSeller, oBuyer, "INV-2026-0001", Date() )
```

`examples/create-invoices-dto.prg` is the exact DTO equivalent of `examples/create-invoices.prg`
from §1.3 — same data, same three tax scenarios, same XRechnung/ZUGFeRD output — with every
`EinvoiceParty`/`EinvoiceAddress`/`EinvoiceLineItem`/`EinvoicePaymentMeans`/
`EinvoicePaymentTerms` built as a `DataObject` instead. Open the two files side by side to see
both styles for the same invoice; pick whichever fits how your own data already arrives (a
`setXXX()` chain reads better when you are filling in values one at a time from program logic,
a `DataObject` is often more natural when mapping a whole record at once).

---

## 3. Validating a document loaded from disk

`ManualEinvoice():createFromString( cXml )` / `:createFromFile( cPath )` load a CII XML
document — XRechnung or ZUGFeRD, same CII content model — back into a fully populated
`ManualEinvoice`, mapping every field `CiiSerializer` can write back via the matching
`setXXX()`/`addXXX()` call. The result is read back out with the ordinary `getXXX()` getters
(`oInvoice:getNumber()`, `:getSeller()`, `:getLines()`, ...), validated with `:validate()` like
any other invoice, and can be re-serialized with `:toXRechnung()`/`:toZugferd()`.

```xbase
LOCAL oInvoice, oResult, oError, nI

BEGIN SEQUENCE
   oInvoice := ManualEinvoice():createFromFile( "received\INV-2026-0001.xrechnung.xml" )
RECOVER USING oError
   ? "Could not load the document: " + oError:description
   RETURN
END SEQUENCE

oResult := oInvoice:validate()
IF oResult:Valid
   ? "Document is valid.", "Grand total:", oResult:Model:Totals:GrandTotal:toFixed(2)
ELSE
   FOR nI := 1 TO Len( oResult:Errors )
      ? "[" + oResult:Errors[nI]:Rule + "] " + oResult:Errors[nI]:Message
   NEXT
ENDIF
```

`:createFromString()`/`:createFromFile()` raise (same `BEGIN SEQUENCE/RECOVER` pattern as
`:toXRechnung()`) on malformed XML, on a document whose root is not
`rsm:CrossIndustryInvoice`, or on an encoding that cannot be scanned as single-byte Character
text at all (`UTF-16`/`UTF-32`) — anything else (`UTF-8`, `windows-1252`, `ISO-8859-1/2`, no
declaration) is accepted best-effort.

**What is different about validating a loaded document:** `:validate()` runs the same EU
content rules, EN 16931 rules and scenario rules as always, **plus** a check only a loaded
document can ever exercise — the real EN 16931 arithmetic-consistency rules **BR-CO-10
through BR-CO-17**, comparing the totals and tax breakdown the document itself states against
what this library independently recomputes from the document's own lines, allowances and
charges. On the normal build path (§1/§2) these two sources are always the same number by
construction, so there is nothing to check; a document you did not build yourself is the
first case where "what it says" and "what its own line items add up to" can genuinely
disagree — a mismatch is reported with the real `BR-CO-1x` rule id, exactly like any other
validation error.

A few things do **not** survive the round trip, by design, not by accident: output is not
byte-identical to the source document (element order follows this library's own writer), a
line's exemption-reason **text** is regenerated from the seller's `EinvoiceCountryProfile`
rather than copied from the source (CII does not restate a line's exemption text individually,
only the aggregated header tax breakdown carries it), and the original sender's scenario
(`DomesticEinvoice` vs. `IntraEuEinvoice` vs. ...) is lost — `:getScenario()` on a loaded
invoice always reads `"MANUAL"`, since CII itself carries the already-resolved VAT category
per line, never the country/kind inputs the automatic scenarios use to derive it.

---

## Appendix: authoritative reference material

### 1. Rules overview (Germany / EU, B2B)

### Timeline

| Date | What applies |
|---|---|
| since 01.01.2025 | Every domestic business must be able to **receive** e-invoices. PDF by e-mail is no longer an "E-Rechnung" but a "sonstige Rechnung". |
| 2025–2026 | Paper/PDF may still be **issued** for domestic B2B (PDF needs the recipient's consent). |
| **01.01.2027** | Issuing e-invoices mandatory for businesses with **> 800 000 € prior-year turnover**. Smaller businesses may still issue paper/PDF (and EDI with consent) during 2027. |
| **01.01.2028** | Issuing e-invoices mandatory for **all** domestic B2B supplies. |
| **01.07.2030** | ViDA (Directive (EU) 2025/516): EN 16931 e-invoices + per-transaction digital reporting mandatory for **intra-EU B2B**; the Zusammenfassende Meldung is replaced. Invoice within 10 days. |

Legal basis: § 14 UStG as amended by the Wachstumschancengesetz; BMF letters of
15.10.2024 and 15.10.2025 (second letter: format requirements, validation, corrections).

**Out of scope of the domestic mandate:** small-amount invoices ≤ 250 € (§ 33 UStDV), tickets
(§ 34 UStDV), tax-exempt supplies under § 4 Nr. 8–29 UStG, B2C, and **cross-border invoices
(DE→EU, DE→third country)** — the mandate only covers supplies between businesses both
established in Germany. Kleinunternehmer (§ 19 UStG) are exempt from *issuing* (§ 34a UStDV)
but must be able to receive.

### Formats

| | XRechnung | ZUGFeRD / Factur-X |
|---|---|---|
| What | German CIUS of EN 16931, pure XML | Hybrid: PDF/A-3 + embedded CII XML |
| Current version | **3.0.2** (valid at least until 31.07.2027; 4.0 pre-release published 15.09.2026, based on EN 16931-1:2026, bundle announced for spring 2027) | **2.5** / Factur-X 1.09 (published 10.06.2026, apply from 01.07.2026; patch 2.5.2 effective 01.09.2026). ZUGFeRD 2.4 / Factur-X 1.08 was in force from 15.01.2026 |
| Syntax | UBL 2.1 **or** CII | CII only |
| Legally relevant part | the XML | the XML (the PDF is only a visualization) |
| Valid as German E-Rechnung | yes | yes for profiles **EN 16931, EXTENDED, XRECHNUNG** (BASIC accepted by many); **not** MINIMUM / BASIC-WL |
| Typical use | B2G (mandatory for federal authorities, Leitweg-ID in BT-10), B2B | B2B, especially SMEs (human-readable) |

New in ZUGFeRD 2.5: CII rule **R74 – no empty XML elements**. This library never emits empty
elements (except the schema-required `<ram:ApplicableHeaderTradeDelivery/>`).

### XRechnung 3.0 additional mandatory fields (BR-DE-*)

- BT-10 **Buyer reference** (Leitweg-ID for public buyers; any agreed reference in B2B) – BR-DE-15
- BG-6 **Seller contact** with name, phone, e-mail – BR-DE-2/5/6/7
- BT-34 / BT-49 **electronic addresses** of seller and buyer (scheme `EM` = e-mail, `0204` = Leitweg-ID …)
- BG-16 **payment instructions** – BR-DE-1; credit transfer needs IBAN
- Seller **VAT ID or tax number** – BR-DE-16
- Type codes 326, 380, 381, 384, 389, 875, 876, 877 only – BR-DE-17
- Skonto in BT-20 as `#SKONTO#TAGE=14#PROZENT=2.00#` + line feed – BR-DE-18
- BT-24 = `urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0`, BT-23 = Peppol billing process

### German content requirements (§ 14 Abs. 4, § 14a UStG) enforced by the library

Full name/address of both parties, seller USt-IdNr. or Steuernummer, invoice number, issue date,
**date of supply or service period**, quantity/description, net amounts per rate, rate and VAT
amount or exemption statement, and for special cases the mandatory statements below.

### Tax scenarios (seen from the seller's country "home")

| Scenario | Class | Line | VAT category (BT-151) | VATEX (BT-121) | Mandatory statement (BT-120 + note), from the seller profile | Extra requirements |
|---|---|---|---|---|---|---|
| home→home standard | `DomesticInvoice` | any | **S** – `vatRate` or profile default (DE 19, AT 20, FR 20) | – | – | DE: e-invoice mandate 2027/2028 |
| home→home zero rate | `DomesticInvoice` | `vatRate: 0` | **Z** | – | – | e.g. DE PV systems § 12 Abs. 3 |
| home→home reverse charge | `DomesticInvoice` | `vatCategory: 'AE'` | **AE** 0 % | VATEX-EU-AE | DE „Steuerschuldnerschaft des Leistungsempfängers (§ 13b UStG)", FR „Autoliquidation", EU Art. 199 | buyer VAT ID or legal ID (BR-AE-02) |
| home→home exempt | `DomesticInvoice` | `vatCategory: 'E'` | **E** 0 % | optional | your exemption reason | |
| small business | any, `seller.smallBusiness` | any | **E** 0 % | – | DE § 19 UStG, AT § 6 Abs. 1 Z 27, FR art. 293 B CGI, EU Art. 284 ff. | |
| home→EU goods | `IntraEuInvoice` | `kind: 'goods'` | **K** 0 % | VATEX-EU-IC | DE § 6a UStG, AT Art. 6 Abs. 1, FR art. 262 ter I CGI, EU Art. 138 | **both VAT IDs** (BR-IC-02), deliver-to country ≠ home (BR-IC-12, defaults to buyer), delivery date (BR-IC-11), transport proof, EC Sales List |
| home→EU services | `IntraEuInvoice` | `kind: 'service'` | **AE** 0 % | VATEX-EU-AE | DE „Steuerschuldnerschaft des Leistungsempfängers", FR „Autoliquidation", EU Art. 196 | both VAT IDs, EC Sales List |
| home→EU, taxable at home (local real estate, events) | `IntraEuInvoice` | `vatCategory: 'S'` | **S** | – | – | |
| home→third country goods | `ExportInvoice` | `kind: 'goods'` | **G** 0 % | VATEX-EU-G | DE § 6 UStG, AT § 7, FR art. 262 I CGI, EU Art. 146 | export proof |
| home→third country services | `ExportInvoice` | `vatCategory: 'O'` | **O** (no rate) | VATEX-EU-O | "not subject to VAT" | O cannot mix with other categories; VAT IDs are suppressed (BR-O-*), tax number required |
| non-EU seller / special cases | `ManualInvoice` | `vatCategory` (+ `vatRate`) on every line | as given | default per category | profile/EU text unless `exemptionReason` given | |

Invoices to EU buyers **without** a VAT ID are B2C-like (home VAT or OSS destination VAT) — the
library refuses to guess and asks for an explicit `vatCategory`.

The AT and FR statements are the commonly used wordings; have them confirmed by a tax
advisor for your business before production use.

### 6. Sources

Retrieved 23–24 Oct 2026. Primary sources (laws, official publications, standard
bodies, validation artefacts) are listed first in each group; secondary sources were
only used for dates/versions and are marked *(secondary)*. Where a site blocks automated
access, the link was taken from search results but its content could not be re-read
by machine — marked *(not machine-verified)*.

### 6.1 German law and administrative guidance

| Claim in this README | Source |
|---|---|
| Definition of „elektronische Rechnung“ (structured format, EN 16931), invoice content requirements (§ 14 Abs. 4 Nr. 1–10: names/addresses, tax no./VAT ID, date of supply, net amounts per rate …) | § 14 UStG – https://www.gesetze-im-internet.de/ustg_1980/__14.html |
| Reverse charge: mandatory wording „Steuerschuldnerschaft des Leistungsempfängers“ (§ 14a Abs. 5); intra-community supply: invoice by the 15th of the following month with **both VAT IDs** (§ 14a Abs. 3). The note on the tax exemption itself comes from § 14 Abs. 4 Nr. 8 | § 14a UStG – https://www.gesetze-im-internet.de/ustg_1980/__14a.html |
| Domestic reverse charge (construction services, scrap metal …) | § 13b UStG – https://www.gesetze-im-internet.de/ustg_1980/__13b.html |
| Intra-community supply exemption / export exemption | § 4 Nr. 1, § 6, § 6a UStG – https://www.gesetze-im-internet.de/ustg_1980/__4.html, https://www.gesetze-im-internet.de/ustg_1980/__6.html, https://www.gesetze-im-internet.de/ustg_1980/__6a.html |
| Small-amount invoices ≤ 250 € may „abweichend von § 14 Absatz 2 Satz 2 des Gesetzes immer als sonstige Rechnung“ be sent (last sentence) | § 33 UStDV – https://www.gesetze-im-internet.de/ustdv_1980/__33.html |
| Tickets (Fahrausweise): same „sonstige Rechnung“ rule | § 34 UStDV – https://www.gesetze-im-internet.de/ustdv_1980/__34.html |
| Kleinunternehmer invoices: reduced content incl. note on the exemption, and may always be sent as „sonstige Rechnung“ (i.e. no e-invoice obligation) | § 34a UStDV – https://www.gesetze-im-internet.de/ustdv_1980/__34a.html |
| Transport proof (Gelangensbestätigung) | § 17a UStDV – https://www.gesetze-im-internet.de/ustdv_1980/__17a.html |
| Transition periods, § 27 Abs. 38 UStG: Nr. 1 paper/other invoices for supplies until 31.12.2026; Nr. 2 in 2027 only if prior-year total turnover ≤ 800 000 €; Nr. 3 EDI with consent until 31.12.2027 | § 27 UStG – https://www.gesetze-im-internet.de/ustg_1980/__27.html |
| BMF letter 15.10.2024 (first application letter: formats XRechnung / ZUGFeRD ≥ 2.0.1 except MINIMUM and BASIC-WL, scope domestic only, transition rules) | Copy hosted by IHK – https://www.ihk.de/blueprint/servlet/resource/blob/6287096/b75ea97a08683f14991b4315c44fee1c/bmf-schreiben-15-10-2024-e-rechnung-data.pdf |
| BMF letter 15.10.2025 (second letter: format requirements, validation, corrections) | https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Umsatzsteuer/Umsatzsteuer-Anwendungserlass/2025-10-15-einfuehrung-obligatorische-e-rechnung.pdf?__blob=publicationFile&v=5 *(not machine-verified)* |
| BMF FAQ on the e-invoice | https://www.bundesfinanzministerium.de/Content/DE/FAQ/e-rechnung.html *(not machine-verified)* |
| Summary of both BMF letters | IHK Köln – https://www.ihk.de/koeln/hauptnavigation/recht-steuern/steuern/bmf-schreiben-zur-e-rechnung-vom-15-10-2025-6774012 *(secondary)*; IHK Stuttgart – https://www.ihk.de/stuttgart/fuer-unternehmen/recht-und-steuern/steuerrecht/steuermeldungen/e-rechnungen-5864496 *(secondary)* |

### 6.2 EU law

| Claim | Source |
|---|---|
| Invoice content rules: Art. 226 (incl. (11) exemption reference, (11a) "Reverse charge"), Art. 138 intra-community supply, Art. 146 export, Art. 196 / 199 reverse charge, Art. 44 place of B2B services, Art. 284 ff. small enterprises | Council Directive 2006/112/EC (VAT Directive) – https://eur-lex.europa.eu/eli/dir/2006/112/oj/eng |
| ViDA: Directive (EU) 2025/516 of 11 March 2025; Member States may mandate domestic e-invoicing without derogation (Art. 1 amending Art. 218/232, from entry into force 14.04.2025); intra-community e-invoicing and digital reporting from **1 July 2030** (Art. 5, new Art. 262–264); invoice within **10 days** (Art. 222 as amended) | https://eur-lex.europa.eu/eli/dir/2025/516/oj/eng (PDF: https://eur-lex.europa.eu/eli/dir/2025/516/oj/eng/pdf) |
| E-invoicing in public procurement, basis for EN 16931 | Directive 2014/55/EU – https://eur-lex.europa.eu/eli/dir/2014/55/oj/eng |

### 6.3 Standards, code lists and validation artefacts

| Claim | Source |
|---|---|
| EN 16931 code lists: VATEX (v9.0), EAS (v17.0), full code list values; validation artefacts v1.3.17 for UBL 2.1 and CII D16B | European Commission, Registry of supporting artefacts – https://ec.europa.eu/digital-building-blocks/sites/display/DIGITAL/Registry+of+supporting+artefacts+to+implement+EN16931 |
| CEN EN 16931 Schematron/XSLT and CII D16B XSD used for validation (tag `validation-1.3.17`) | https://github.com/ConnectingEurope/eInvoicing-EN16931 |
| XRechnung is maintained by KoSIT on behalf of the IT-Planungsrat | https://e-rechnung-bund.de/en/faq/who-maintains-the-xrechnung-standard/ |
| XRechnung Schematron (BR-DE-*, BR-TMP-*), v2.6.0 of 31.08.2026, compatible with XRechnung 3.0, uses CEN 1.3.16 code lists and Peppol BIS Billing 3.0.21 | https://github.com/itplr-kosit/xrechnung-schematron (CHANGELOG.md) |
| Official KoSIT validator and XRechnung validator configuration (recommended for production) | https://github.com/itplr-kosit/validator, https://github.com/itplr-kosit/validator-configuration-xrechnung |
| XRechnung 3.0.2 current; 4.0 pre-release 15.09.2026 based on EN 16931-1:2026; version 3.0 stays valid at least until 31.07.2027; bundle for 4.0 announced for spring 2027 | Agicap – https://agicap.com/de/artikel/xrechnung/ *(secondary)*; KoSIT/E-Rechnung Bund news – https://e-rechnung-bund.de/en/faq_category/xrechnung/ |
| Peppol BIS Billing 3.0 (rules PEPPOL-EN16931-R010/R020 adopted by XRechnung; business process ID BT-23) | https://docs.peppol.eu/poacc/billing/3.0/2022-Q4/bis |
| ISO Schematron skeleton used for validation | https://github.com/Schematron/schematron |

### 6.4 ZUGFeRD / Factur-X

| Claim | Source |
|---|---|
| ZUGFeRD 2.4 / Factur-X 1.08 published 04.12.2025, in force 15.01.2026 | FNFE-MPE press release – https://fnfe-mpe.org/wp-content/uploads/2025/12/2025-12-04_Factur-X_1.08_ZUGFeRD_2.4_Press_Release_EN.pdf |
| ZUGFeRD 2.5 / Factur-X 1.09 published 10.06.2026 (updated code lists/validation artefacts, new EXTENDED elements); note on empty XML elements (CII rule R74) | FeRD press release – https://www.ferd-net.de/fileadmin/user_upload/FeRD/f%C3%BCr_FeRD-Meldungen/20260610_ZUGFeRD_2_5_Factur-X_1_09_Press_Release_DE.pdf; FeRD package page – https://www.ferd-net.de/en/downloads/publications/details/zugferd-25-english |
| Recommended from 01.07.2026; based on CII D22B, backwards compatible | VATupdate – https://www.vatupdate.com/?p=355628 *(secondary)* |
| ZUGFeRD 2.5.2 corrigendum published 04.08.2026, effective 01.09.2026; next release (gross invoices, EN 16931 revision) expected autumn 2026 | https://www.ferd-net.de/en/downloads/publications/details/zugferd-252-english |
| ZUGFeRD and Factur-X technically identical; downloads | https://www.ferd-net.de/ZUGFeRD-Download, https://fnfe-mpe.org/factur-x/factur-x_en/ |

### 6.5 Country profiles

| Profile | Statement | Source |
|---|---|---|
| DE | § 6a, § 6, § 13b, § 19 UStG wordings | links in 6.1; § 19 UStG – https://www.gesetze-im-internet.de/ustg_1980/__19.html |
| FR | „Exonération de TVA, article 262 ter I du CGI“ and „Autoliquidation“ (plus both VAT numbers) are mandatory mentions | BOFiP BOI-TVA-DECLA-30-20-20-30 – https://bofip.impots.gouv.fr/doctrine/pgp/1531-PGP%23Mentions_obligatoires_24 |
| FR | Export „article 262 I du CGI“, small business „TVA non applicable, art. 293 B du CGI“ | Code général des impôts on Légifrance – https://www.legifrance.gouv.fr/codes/texte_lc/LEGITEXT000006069577/ *(not machine-verified)* |
| AT | Art. 6 Abs. 1 (ig. Lieferung), § 7 (Ausfuhr), § 6 Abs. 1 Z 27 (Kleinunternehmer), § 11 (invoice content incl. „Übergang der Steuerschuld“), § 19 (reverse charge) | Umsatzsteuergesetz 1994, RIS – https://www.ris.bka.gv.at/GeltendeFassung.wxe?Abfrage=Bundesnormen&Gesetzesnummer=10004873 *(not machine-verified)* |
| EU fallback | Art. 138, 146, 196, 199, 226, 284 ff. Directive 2006/112/EC | link in 6.2 |

The AT and FR wordings follow the cited provisions but are not certified by those
administrations — have them reviewed by a tax advisor before production use. (This Xbase++
module's own `DE`/`AT`/`FR` `EinvoiceCountryProfile` statements are the same wordings, 
transliterated to plain ASCII to avoid a source-file codepage mismatch
— the legal/semantic meaning is unchanged.)

### 6.6 How to re-check

1. **Law texts:** open the links in 6.1/6.2; German statute pages are the official
   consolidated versions of the Federal Ministry of Justice.
2. **XML validity:** clone the three repositories from 6.3 and run
   `python3 tools/validate.py <dir> out/*.xml`, or use the official KoSIT validator with the
   XRechnung configuration:
   `java -jar validator-<v>-standalone.jar -s scenarios.xml -r <config-dir> out/*.xrechnung.xml`.
3. **Versions:** compare the CEN registry (6.3) and FeRD download page (6.4) with the
   versions named here; both publish updates roughly every six months.

---

Copyright 2026 Alaska Software. All rights reserved.
