# create-invoices.prg

Intro sample for the e-invoice framework (`alaska-software.e-invoice-factory.dll`): turns one
Northwind (extended) order invoice - plain DBF rows under `e-invoice\examples\data\` - into
XRechnung and ZUGFeRD XML. The point of the sample is `EinvFactory():createInvoice()` (see
`CreateEInvoice()`): given only the seller's and the buyer's address, it alone decides the tax
scenario - domestic, intra-EU or export - and the three demo invoices below exercise exactly
those three cases for a single German seller, Northwind Inc., Berlin (built in `Main()`).

This file builds every `EinvoiceAddress`/`EinvoiceParty`/`EinvoiceLineItem`/
`EinvoicePaymentMeans`/`EinvoicePaymentTerms` with its own documented `setXXX()` methods.
`create-invoices-dto.prg` is the same intro sample - same data, same three automatic tax
scenarios, same XRechnung/ZUGFeRD output - but builds every one of those objects as a plain
`DataObject` instead. Compare the two files side by side to see both ways
`EinvFactory():createInvoice()` can be fed.

## The shape to copy for your own integration

`CreateEInvoice()` reads one order from your own tables and calls
`EinvoiceParty():new():setName(...):setAddress(...)` etc. for the buyer and its line items,
then `EinvFactory():createInvoice()` to get back a ready `AbstractEinvoice`. It does nothing
else - no validation, no XML, no file I/O - so it drops into your own code unchanged once the
DBF-specific lines are swapped for your tables.

`oInvoice:validate()` never raises - it reports every problem with its own EN 16931/XRechnung
rule id, so `Main()` can print all of them at once; it is called directly in `Main()`, right
where the outcome decides whether to save.

`SaveEInvoice()` calls `:toXRechnung()`/`:toZugferd()`, which DO raise once a validation error
remains at that point - guard every such call site, as done here.

`Main()` wires these together per invoice id and reports a per-invoice summary plus a final
succeeded/failed count.

## Demo invoices (real rows in the shipped Northwind data)

| Invoice         | Customer | Location          | Scenario           | Tax                  |
|-----------------|----------|--------------------|---------------------|-----------------------|
| INV-2024-00011  | TOMSP    | Munster, Germany   | `DomesticEinvoice`  | 19% VAT               |
| INV-2024-00005  | SUNN4    | Wroclaw, Poland    | `IntraEuEinvoice`   | VAT-exempt (K)        |
| INV-2024-00002  | ORCH4    | Austin, USA        | `ExportEinvoice`    | VAT-exempt (G)        |

## Usage

```
create-invoices.exe [cDataPath] [cOutDir]
```

- `cDataPath` - directory containing the Northwind DBF tables (default `.\data\`)
- `cOutDir` - directory the `.xrechnung.xml`/`.zugferd.xml` files are written to (default `.\`)

## What the code does

- `DBESYS` - loads and builds the `FOXCDX`; the shipped Northwind data is FOXCDX only.
- `Main()` - builds the seller (Northwind Inc., Berlin, Germany) once, then for each of the
  three demo invoice ids: builds the invoice via `CreateEInvoice()`, prints the scenario
  `EinvFactory()` picked, runs `oInvoice:validate()` and prints every error/warning with its
  rule id, and - only when valid - saves it via `SaveEInvoice()`. Finishes with a
  succeeded/failed count.
- `CreateEInvoice( oSeller, cInvoiceId, cDataPath )` - looks up `cInvoiceId` and its customer
  and line items in `customers.dbf`/`invoices.dbf`/`invoicedetails.dbf`, maps the customer's
  country name to an ISO-3166 alpha-2 code via `NwCountryToIso2()`, builds the buyer
  `EinvoiceAddress`/`EinvoiceParty`, calls `EinvFactory():createInvoice()` to get the
  `AbstractEinvoice`, then adds currency, buyer reference, delivery date, payment terms,
  Northwind Inc.'s own (fictitious) SEPA payment means, and every line item. Returns `NIL`
  (and prints a diagnostic) when the invoice id, its customer, or its country cannot be
  resolved.
- `SaveEInvoice( oInvoice, cXRechnungFile, cZugferdFile )` - writes both files from
  `oInvoice:toXRechnung()`/`:toZugferd( "EN16931" )`. Both calls run their own extra,
  format-specific checks (e.g. XRechnung's PEPPOL-EN16931-R010/R020) on top of `:validate()`
  and RAISE if those find an error, so each call is guarded in its own `BEGIN SEQUENCE`.
  Returns `.T.` only when both files were written.
- `NwCountryToIso2( cCountry )` - maps the English country name stored in
  `customers.dbf->country` to its ISO-3166 alpha-2 code, for the subset of countries actually
  present in the shipped Northwind (extended) sample data. Returns `""` for a name not in that
  list.

## Copyright

Copyright 2026 Alaska Software. All rights reserved.
