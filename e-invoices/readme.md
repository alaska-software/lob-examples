# Xbase++ E-Invoice Examples

Xbase++ Professional Edition ships with an **e-invoice-factory** asset
(`alaska-software.e-invoice-factory.dll`) that builds and reads **EN 16931** e-invoices -
**XRechnung 3.0** or **ZUGFeRD 2.x / Factur-X** - from/to an in-memory invoice model, with
no PDF, no DBF tables and no network calls involved.

This repository is a small, runnable, self-contained pair of examples that show the asset in
use: both turn the same Northwind (extended) order data into XRechnung and ZUGFeRD XML for a
domestic, an intra-EU and an export invoice, `EinvFactory():createInvoice()` picking the right
tax scenario from the seller's and the buyer's country alone - one example builds the invoice
model with `setXXX()` builder calls, the other builds the very same model as plain
`DataObject` DTOs, so the two files can be read side by side to compare both styles.

> **Prerequisite:** these examples need **Xbase++ Professional Edition V2.2920 or higher**
> (the version the `e-invoice-factory` asset ships with).

## Checkout

```bat
git clone https://github.com/alaska-software/lob-examples.git
cd lob-examples/e-invoices
```

## Build and Run

**1. Install the asset and build**

**1.1 V3 only**

```bat
xppam PROJECT -install
pbuild project.xpj
```

**1.2 V2 only**

- load project into Xbase++ Workbench
- Open Asset Manager on each target, add/update the e-Incoice asset
- Build project

```bat
xppam PROJECT -install
pbuild project.xpj
```


**2. Run an example**

```bat
create-invoices.exe
create-invoices-dto.exe
```

Both write their `.xrechnung.xml`/`.zugferd.xml` output next to the executable.

## What's In

| Target | What it does | How it does it |
|---|---|---|
| `create-invoices.exe` | Reads one Northwind order per demo invoice and writes a domestic, an intra-EU and an export XRechnung/ZUGFeRD file. | Builds every `EinvoiceAddress`/`EinvoiceParty`/`EinvoiceLineItem`/`EinvoicePaymentMeans`/`EinvoicePaymentTerms` through its own `setXXX()` methods, then calls `EinvFactory():createInvoice()`. |
| `create-invoices-dto.exe` | The same three demo invoices, the same XRechnung/ZUGFeRD output. | Builds every one of those same objects as a plain `DataObject` instead of calling `setXXX()`. |

## Documentation

- [`e-invoice-factory-usage-guide.md`](e-invoice-factory-usage-guide.md) in this repository
  walks through creating an invoice, building the model either as objects or as DTOs, and
  validating a document loaded from disk.
- The full method-by-method reference for the asset is in the "eInvoice" group of the
  Xbase++ reference documentation: https://doc.alaska-software.com/v2/content/grp_toc_l2_xrechnung.cxp

## Copyright

Copyright 2026 Alaska Software. All rights reserved.
