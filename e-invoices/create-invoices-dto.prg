//////////////////////////////////////////////////////////////////////
///
/// <summary>
/// Intro sample for the e-invoice framework
/// (`alaska-software.e-invoice-factory.dll`): turns one Northwind
/// (extended) order invoice - plain DBF rows under
/// `e-invoice\examples\data\` - into XRechnung and ZUGFeRD XML. The
/// point of the sample is `EinvFactory():createInvoice()` (see
/// `CreateEInvoice()`): given only the seller's and the buyer's
/// address, it alone decides the tax scenario - domestic, intra-EU or
/// export - and the three demo invoices below exercise exactly those
/// three cases for a single German seller, Northwind Inc., Berlin
/// (built in `Main()`).
/// </summary>
///
/// <remarks>
/// The shape to copy for your own integration:
///   `CreateEInvoice()` reads one order from your own tables, maps it
///   onto the plain `DataObject`s that `EinvoiceParty`/`EinvoiceAddress`/
///   `EinvoiceLineItem` take, and calls `EinvFactory():createInvoice()`
///   to get back a ready `AbstractEinvoice`. It does nothing else - no
///   validation, no XML, no file I/O - so it drops into your own code
///   unchanged once the DBF-specific lines are swapped for your tables.
///   `ValidateEInvoice()` calls `:validate()` and reports the result;
///   that call never raises. `SaveEInvoice()` calls `:toXRechnung()`/
///   `:toZugferd()`, which DO raise once a validation error remains at
///   that point - guard every such call site, as done here.
/// `Main()` wires the three together per invoice id and reports a
/// per-invoice summary plus a final succeeded/failed count.
///
/// Demo invoices (real rows in the shipped Northwind data):
///   INV-2024-00011  TOMSP, Munster, Germany -> DomesticEinvoice, 19% VAT
///   INV-2024-00005  SUNN4, Wroclaw, Poland   -> IntraEuEinvoice, VAT-exempt (K)
///   INV-2024-00002  ORCH4, Austin, USA       -> ExportEinvoice, VAT-exempt (G)
///
/// Usage: create-invoices.exe [cDataPath] [cOutDir]
/// </remarks>
///
/// <copyright>
/// Copyright 2026 Alaska Software. All rights reserved.
/// </copyright>
///
//////////////////////////////////////////////////////////////////////

#include "common.ch"
#include "..\einvoice-codes.ch"

/// <summary>
/// Same DBE/RDD setup as the other Northwind-data use cases - see 
/// e.g. create-invoice.prg's own PROCEDURE DBESYS.
/// </summary>
PROCEDURE DBESYS
   DbeLoad( "FOXDBE" )
   DbeLoad( "CDXDBE" )
   DbeBuild( "FOXCDX", "FOXDBE", "CDXDBE" )
RETURN

PROCEDURE Main( cDataPath, cOutDir )
   LOCAL oSeller
   LOCAL oSellerAddr
   LOCAL oSellerContact
   LOCAL aInvoiceIds
   LOCAL cInvoiceId
   LOCAL oInvoice
   LOCAL oModel
   LOCAL oResult
   LOCAL lOk
   LOCAL nI
   LOCAL nOk := 0
   LOCAL nFail := 0

   DEFAULT cDataPath TO ".\data\"
   DEFAULT cOutDir   TO ".\"

   // The framework takes Character text as UTF-8 and converts it itself
   // (Char2Utf8(), honouring whatever SET CHARSET currently names as
   // your data's codepage) - set this to match your own tables before
   // building any EinvoiceParty/EinvoiceAddress/EinvoiceLineItem. These
   // Northwind DBFs are ANSI/cp1252, hence ANSI here.
   SET CHARSET TO ANSI

   // Seller (BG-4) - Northwind Inc., Germany, Berlin (fictitious). Same
   // EinvoiceParty/EinvoiceAddress DataObject shape as the buyer
   // CreateEInvoice() builds below from the customer row.
   oSellerAddr := DataObject():new()
   oSellerAddr:Line1       := "Alexanderplatz 7"
   oSellerAddr:Postcode    := "10178"
   oSellerAddr:City        := "Berlin"
   oSellerAddr:CountryCode := "DE"

   oSellerContact := DataObject():new()
   oSellerContact:Name  := "Accounting"
   oSellerContact:Phone := "+49 30 1234567-0"
   oSellerContact:Email := "invoicing@northwind-inc.example"

   oSeller := DataObject():new()
   oSeller:Name              := "Northwind Inc., Germany"
   oSeller:VatId             := "DE123456789"
   oSeller:Address           := oSellerAddr
   oSeller:Contact           := oSellerContact
   oSeller:ElectronicAddress := "invoicing@northwind-inc.example"

   // One real invoice id per automatic tax scenario (see class remarks)
   aInvoiceIds := { "INV-2024-00011", "INV-2024-00005", "INV-2024-00002" }

   FOR nI := 1 TO Len( aInvoiceIds )
      cInvoiceId := aInvoiceIds[nI]
      ? "=========================================================="

      oInvoice := CreateEInvoice( oSeller, cInvoiceId, cDataPath )
      IF oInvoice == NIL
         nFail++
         LOOP
      ENDIF

      // :getScenario() and :toModel() are the framework's own read-only
      // accessors for what EinvFactory() decided and calculated.
      oModel := oInvoice:toModel()
      ? "Invoice", cInvoiceId, "-", oInvoice:getScenario(), ;
        " seller=" + oSeller:Address:CountryCode + " buyer=" + oModel:Buyer:getCountryCode(), ;
        " currency=" + oModel:Currency

      oResult := ValidateEInvoice( oInvoice )

      IF oResult:Valid
         lOk := SaveEInvoice( oInvoice, cOutDir + cInvoiceId + ".xrechnung.xml", cOutDir + cInvoiceId + ".zugferd.xml" )
      ELSE
         ? "  XRechnung/ZUGFeRD: skipped (invoice has validation errors)"
         lOk := .F.
      ENDIF

      IF lOk
         nOk++
      ELSE
         nFail++
      ENDIF
   NEXT

   ? "=========================================================="
   ? "Done:", nOk, "succeeded,", nFail, "failed"
RETURN


/// <summary>
/// Loads invoice `cInvoiceId` (`invoices->invoiceno`) and its customer/
/// line items from the Northwind DBF tables under `cDataPath`, and
/// builds the matching `AbstractEinvoice` via `EinvFactory():
/// createInvoice()` (the seller's and buyer's country code alone pick
/// Domestic/IntraEu/Export). A single concern - build and return the
/// invoice, nothing else: no `:validate()`, no XML/file I/O (see
/// `ValidateEInvoice()`/`SaveEInvoice()`, called from `Main()`).
/// Returns NIL (and prints a diagnostic) when the invoice id, its
/// customer, or its country cannot be resolved.
/// </summary>
FUNCTION CreateEInvoice( oSeller, cInvoiceId, cDataPath )
   LOCAL cCustomersDbf
   LOCAL cCustomersCdx
   LOCAL cInvoicesDbf
   LOCAL cInvoicesCdx
   LOCAL cInvDetDbf
   LOCAL cInvDetCdx
   LOCAL nInvoiceId
   LOCAL cCustomerId
   LOCAL cCountryCode
   LOCAL oBuyer
   LOCAL oBuyerAddr
   LOCAL oInvoice
   LOCAL oPaymentTerms
   LOCAL oLineData

   cCustomersDbf := cDataPath + "customers.dbf"
   cCustomersCdx := cDataPath + "customers.cdx"
   cInvoicesDbf  := cDataPath + "invoices.dbf"
   cInvoicesCdx  := cDataPath + "invoices.cdx"
   cInvDetDbf    := cDataPath + "invoicedetails.dbf"
   cInvDetCdx    := cDataPath + "invoicedetails.cdx"

   IF !File( cCustomersDbf ) .OR. !File( cInvoicesDbf ) .OR. !File( cInvDetDbf )
      ? "CreateEInvoice() - one or more DBF files not found under", cDataPath
      RETURN NIL
   ENDIF

   USE (cCustomersDbf) INDEX (cCustomersCdx) ALIAS nwcustomers NEW VIA FOXCDX
   USE (cInvoicesDbf) INDEX (cInvoicesCdx) ALIAS nwinvoices NEW VIA FOXCDX
   USE (cInvDetDbf) INDEX (cInvDetCdx) ALIAS nwinvdet NEW VIA FOXCDX

   IF !Used( "nwcustomers" ) .OR. !Used( "nwinvoices" ) .OR. !Used( "nwinvdet" )
      ? "CreateEInvoice() - could not open the Northwind DBF tables under", cDataPath
      CloseNwTables()
      RETURN NIL
   ENDIF

   nwcustomers->( OrdSetFocus( "customerid" ) )
   nwinvoices->( OrdSetFocus( "invoiceno" ) )
   nwinvdet->( OrdSetFocus( "invoiceid" ) )

   IF !nwinvoices->( DbSeek( cInvoiceId ) )
      ? "CreateEInvoice() - invoice id not found:", cInvoiceId
      CloseNwTables()
      RETURN NIL
   ENDIF

   nInvoiceId  := nwinvoices->invoiceid
   cCustomerId := AllTrim( nwinvoices->customerid )

   IF !nwcustomers->( DbSeek( cCustomerId ) )
      ? "CreateEInvoice() - customer id not found:", cCustomerId
      CloseNwTables()
      RETURN NIL
   ENDIF

   cCountryCode := NwCountryToIso2( AllTrim( nwcustomers->country ) )
   IF Empty( cCountryCode )
      ? "CreateEInvoice() - unknown country, no ISO code mapping:", AllTrim( nwcustomers->country )
      CloseNwTables()
      RETURN NIL
   ENDIF

   // EinvoiceAddress: only CountryCode is required - EinvFactory() needs
   // it to pick the scenario; the rest is address content.
   oBuyerAddr := DataObject():new()
   oBuyerAddr:Line1       := AllTrim( nwcustomers->address )
   oBuyerAddr:City        := AllTrim( nwcustomers->city )
   oBuyerAddr:Postcode    := AllTrim( nwcustomers->postalcode )
   oBuyerAddr:CountryCode := cCountryCode

   // EinvoiceParty (BG-7, the buyer): Name and Address are always
   // required; VatId becomes mandatory the moment the scenario turns out
   // to be intra-EU (BR-IC-02) - see :validate() in ValidateEInvoice().
   oBuyer := DataObject():new()
   oBuyer:Id                := cCustomerId
   oBuyer:Name              := AllTrim( nwcustomers->companynam )
   oBuyer:VatId             := IIF( Empty( AllTrim( nwcustomers->vatid ) ), NIL, AllTrim( nwcustomers->vatid ) )
   oBuyer:Address           := oBuyerAddr

   // customers.dbf has no EMAIL field of its own, but XRechnung's
   // PEPPOL-EN16931-R010 rule requires a buyer electronic address
   // (BT-49) regardless - synthesize one when your own data has none.
   oBuyer:ElectronicAddress := Lower( cCustomerId ) + "@customer.example"

   // The one call this sample is about: EinvFactory() looks at oSeller's
   // and oBuyer's CountryCode and returns a DomesticEinvoice/
   // IntraEuEinvoice/ExportEinvoice already carrying both parties -
   // everything else in this function is plain data mapping.
   oInvoice := EinvFactory():createInvoice( oSeller, oBuyer, cInvoiceId, nwinvoices->issuedate )

   oInvoice:setCurrency( AllTrim( nwinvoices->currency ) )
   oInvoice:setBuyerReference( cCustomerId )
   oInvoice:setDeliveryDate( nwinvoices->issuedate )

   oPaymentTerms := DataObject():new()
   oPaymentTerms:DueDate := nwinvoices->duedate
   oInvoice:setPaymentTerms( oPaymentTerms )

   oInvoice:setPaymentMeans( BuildNwPaymentMeans() )

   IF nwinvdet->( DbSeek( nInvoiceId ) )
      DO WHILE !nwinvdet->( Eof() ) .AND. nwinvdet->invoiceid == nInvoiceId
         oLineData := DataObject():new()
         oLineData:Name         := AllTrim( nwinvdet->itemname )
         oLineData:SellerItemId := AllTrim( Str( nwinvdet->productid ) )
         oLineData:Quantity     := nwinvdet->quantity
         oLineData:Price        := nwinvdet->netamount / nwinvdet->quantity
         oInvoice:addLineItem( oLineData )
         nwinvdet->( DbSkip() )
      ENDDO
   ENDIF

   CloseNwTables()

RETURN oInvoice

/// <summary>
/// Runs oInvoice:validate() and prints the outcome - "OK" (with a
/// warning count when there is one) or every error/warning with its
/// rule id - the single concern `Main()` delegates here so it only has
/// to look at the returned :Valid. Never raises - :validate() itself
/// never does.
/// </summary>
STATIC FUNCTION ValidateEInvoice( oInvoice )
   LOCAL oResult := oInvoice:validate()
   LOCAL nI

   IF oResult:Valid
      ? "  validate(): OK", IIF( Len( oResult:Warnings ) > 0, "(" + AllTrim( Str( Len( oResult:Warnings ) ) ) + " warning(s))", "" )
   ELSE
      ? "  validate(): " + AllTrim( Str( Len( oResult:Errors ) ) ) + " error(s):"
      FOR nI := 1 TO Len( oResult:Errors )
         ? "    [" + oResult:Errors[nI]:Rule + "] " + oResult:Errors[nI]:Message
      NEXT
   ENDIF
   FOR nI := 1 TO Len( oResult:Warnings )
      ? "    warn [" + oResult:Warnings[nI]:Rule + "] " + oResult:Warnings[nI]:Message
   NEXT

RETURN oResult

/// <summary>
/// Writes cXRechnungFile/cZugferdFile from oInvoice:toXRechnung()/
/// :toZugferd("EN16931") - call only once oInvoice has passed
/// ValidateEInvoice(). Both calls run their own extra, format-specific
/// checks (e.g. XRechnung's PEPPOL-EN16931-R010/R020) on top of that
/// validation and RAISE if those find an error - guarded here, one
/// BEGIN SEQUENCE per file, so a surprise prints a diagnostic instead
/// of taking down the whole batch. Returns .T. only when both files
/// were written.
/// </summary>
STATIC FUNCTION SaveEInvoice( oInvoice, cXRechnungFile, cZugferdFile )
   LOCAL cXRechnungXml := NIL
   LOCAL cZugferdXml := NIL
   LOCAL oError
   LOCAL nHandle
   LOCAL lOk := .T.

   BEGIN SEQUENCE
      cXRechnungXml := oInvoice:toXRechnung()
   RECOVER USING oError
      ? "  XRechnung: FAILED - " + oError:description
   END SEQUENCE

   IF cXRechnungXml != NIL
      nHandle := FCreate( cXRechnungFile )
      FWrite( nHandle, cXRechnungXml )
      FClose( nHandle )
      ? "  XRechnung: " + cXRechnungFile
   ELSE
      lOk := .F.
   ENDIF

   BEGIN SEQUENCE
      cZugferdXml := oInvoice:toZugferd( "EN16931" )
   RECOVER USING oError
      ? "  ZUGFeRD: FAILED - " + oError:description
   END SEQUENCE

   IF cZugferdXml != NIL
      nHandle := FCreate( cZugferdFile )
      FWrite( nHandle, cZugferdXml )
      FClose( nHandle )
      ? "  ZUGFeRD:   " + cZugferdFile
   ELSE
      lOk := .F.
   ENDIF

RETURN lOk

/// <summary>Closes the three aliases CreateEInvoice() may have opened, whichever of them are currently open.</summary>
STATIC FUNCTION CloseNwTables()
   IF Used( "nwcustomers" )
      nwcustomers->( DbCloseArea() )
   ENDIF
   IF Used( "nwinvoices" )
      nwinvoices->( DbCloseArea() )
   ENDIF
   IF Used( "nwinvdet" )
      nwinvdet->( DbCloseArea() )
   ENDIF
RETURN NIL

/// <summary>Northwind Inc.'s own (fictitious) bank account - the BG-16 payment instructions on every demo invoice.</summary>
STATIC FUNCTION BuildNwPaymentMeans()
   LOCAL o := DataObject():new()
   o:Code        := EINV_PAYMEANS_SEPA_CREDIT_TRANSFER
   o:Iban        := "DE67 5004 0000 0388 5209 00"
   o:Bic         := "COBADEFFXXX"
   o:AccountName := "Northwind Inc."
RETURN o

/// <summary>
/// Maps the English country name stored in `customers.dbf->country` to
/// its ISO-3166 alpha-2 code - the subset of countries actually present
/// in the shipped Northwind (extended) sample data (verified against
/// the DBF itself). Returns "" for a name not in that list.
/// </summary>
STATIC FUNCTION NwCountryToIso2( cCountry )
   LOCAL aMap := { ;
      {"GERMANY",     "DE"}, ;
      {"FRANCE",      "FR"}, ;
      {"SPAIN",       "ES"}, ;
      {"ITALY",       "IT"}, ;
      {"NETHERLANDS", "NL"}, ;
      {"SWEDEN",      "SE"}, ;
      {"AUSTRIA",     "AT"}, ;
      {"POLAND",      "PL"}, ;
      {"IRELAND",     "IE"}, ;
      {"DENMARK",     "DK"}, ;
      {"PORTUGAL",    "PT"}, ;
      {"FINLAND",     "FI"}, ;
      {"BELGIUM",     "BE"}, ;
      {"CZECHIA",     "CZ"}, ;
      {"USA",         "US"}, ;
      {"UK",          "GB"}, ;
      {"SWITZERLAND", "CH"}, ;
      {"BRAZIL",      "BR"}, ;
      {"CANADA",      "CA"}, ;
      {"MEXICO",      "MX"}, ;
      {"AUSTRALIA",   "AU"}, ;
      {"NORWAY",      "NO"}, ;
      {"JAPAN",       "JP"}, ;
      {"ARGENTINA",   "AR"}, ;
      {"SINGAPORE",   "SG"}, ;
      {"VENEZUELA",   "VE"} }
   LOCAL nPos := AScan( aMap, {|a| a[1] == Upper( cCountry )} )

   IF nPos > 0
      RETURN aMap[nPos][2]
   ENDIF

RETURN ""
