//////////////////////////////////////////////////////////////////////
///
/// <summary>
/// Intro sample for the e-invoice framework: builds XRechnung/ZUGFeRD
/// invoices from Northwind demo data via EinvFactory():createInvoice(),
/// using the setXXX() builder style (see create-invoices.README.md for
/// details).
/// </summary>
///
/// <copyright>
/// Copyright 2026 Alaska Software. All rights reserved.
/// </copyright>
///
//////////////////////////////////////////////////////////////////////

#include "common.ch"
#include "..\einvoice-codes.ch"

/// <summary>
/// Northwind-data is FOXCDX only
/// </summary>
///
PROCEDURE DBESYS
   DbeLoad( "FOXDBE" )
   DbeLoad( "CDXDBE" )
   DbeBuild( "FOXCDX", "FOXDBE", "CDXDBE" )
RETURN

PROCEDURE Main( cDataPath, cOutDir )
   LOCAL oSeller
   LOCAL aInvoiceIds
   LOCAL cInvoiceId
   LOCAL oInvoice
   LOCAL oModel
   LOCAL oResult
   LOCAL lOk
   LOCAL nI
   LOCAL nJ
   LOCAL nOk := 0
   LOCAL nFail := 0

   DEFAULT cDataPath TO ".\data\"
   DEFAULT cOutDir   TO ".\"

   SET CHARSET TO ANSI

   // Seller (BG-4) - Northwind Inc., Germany, Berlin (fictitious). Built
   // with setXXX() instead of a DataObject - see EinvoiceParty's own
   // class remarks.
   oSeller := EinvoiceParty():new()
   oSeller:setName( "Northwind Inc., Germany" )
   oSeller:setVatId( "DE123456YY" )
   oSeller:setAddress( EinvoiceAddress():new():setLine1( "Alexanderplatz 7" ):setPostcode( "10178" ):setCity( "Berlin" ):setCountryCode( "DE" ) )
   oSeller:setContact( "Accounting", "+49 30 1234567-0", "invoicing@northwind-inc.example" )
   oSeller:setElectronicAddress( "invoicing@northwind-inc.example" )

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
        " seller=" + oSeller:getCountryCode() + " buyer=" + oModel:Buyer:getCountryCode(), ;
        " currency=" + oModel:Currency

      // oInvoice:validate() never raises - it reports every problem,
      // each with its own EN 16931/XRechnung rule id, so every issue can
      // be printed at once instead of stopping at the first.
      oResult := oInvoice:validate()
      IF oResult:Valid
         ? "  validate(): OK", IIF( Len( oResult:Warnings ) > 0, "(" + AllTrim( Str( Len( oResult:Warnings ) ) ) + " warning(s))", "" )
      ELSE
         ? "  validate(): " + AllTrim( Str( Len( oResult:Errors ) ) ) + " error(s):"
         FOR nJ := 1 TO Len( oResult:Errors )
            ? "    [" + oResult:Errors[nJ]:Rule + "] " + oResult:Errors[nJ]:Message
         NEXT
      ENDIF
      FOR nJ := 1 TO Len( oResult:Warnings )
         ? "    warn [" + oResult:Warnings[nJ]:Rule + "] " + oResult:Warnings[nJ]:Message
      NEXT

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
/// invoice, nothing else: no `:validate()`, no XML/file I/O (both done
/// directly in `Main()`/`SaveEInvoice()`). Returns NIL (and prints a
/// diagnostic) when the invoice id, its customer, or its country
/// cannot be resolved.
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
   LOCAL oPaymentMeans
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
      DbCloseAll()
      RETURN NIL
   ENDIF

   nwcustomers->( OrdSetFocus( "customerid" ) )
   nwinvoices->( OrdSetFocus( "invoiceno" ) )
   nwinvdet->( OrdSetFocus( "invoiceid" ) )

   IF !nwinvoices->( DbSeek( cInvoiceId ) )
      ? "CreateEInvoice() - invoice id not found:", cInvoiceId
      DbCloseAll()
      RETURN NIL
   ENDIF

   nInvoiceId  := nwinvoices->invoiceid
   cCustomerId := AllTrim( nwinvoices->customerid )

   IF !nwcustomers->( DbSeek( cCustomerId ) )
      ? "CreateEInvoice() - customer id not found:", cCustomerId
      DbCloseAll()
      RETURN NIL
   ENDIF

   cCountryCode := NwCountryToIso2( AllTrim( nwcustomers->country ) )
   IF Empty( cCountryCode )
      ? "CreateEInvoice() - unknown country, no ISO code mapping:", AllTrim( nwcustomers->country )
      DbCloseAll()
      RETURN NIL
   ENDIF

   // EinvoiceAddress, built with setXXX() instead of a DataObject - only
   // CountryCode is required: EinvFactory() needs it to pick the
   // scenario, the rest is just address content.
   oBuyerAddr := EinvoiceAddress():new()
   oBuyerAddr:setLine1( AllTrim( nwcustomers->address ) )
   oBuyerAddr:setCity( AllTrim( nwcustomers->city ) )
   oBuyerAddr:setPostcode( AllTrim( nwcustomers->postalcode ) )
   oBuyerAddr:setCountryCode( cCountryCode )

   // EinvoiceParty (BG-7, the buyer), built with setXXX() instead of a
   // DataObject. Name and Address are always required; VatId becomes
   // mandatory the moment the scenario turns out to be intra-EU
   // (BR-IC-02) - see oInvoice:validate() in Main().
   oBuyer := EinvoiceParty():new()
   oBuyer:setId( cCustomerId )
   oBuyer:setName( AllTrim( nwcustomers->companynam ) )
   IF !Empty( AllTrim( nwcustomers->vatid ) )
      oBuyer:setVatId( AllTrim( nwcustomers->vatid ) )
   ENDIF
   oBuyer:setAddress( oBuyerAddr )

   // customers.dbf has no EMAIL field of its own, but XRechnung's
   // PEPPOL-EN16931-R010 rule requires a buyer electronic address
   // (BT-49) regardless - synthesize one when your own data has none.
   oBuyer:setElectronicAddress( Lower( cCustomerId ) + "@customer.example" )

   // The one call this sample is about: EinvFactory() looks at oSeller's
   // and oBuyer's CountryCode and returns a DomesticEinvoice/
   // IntraEuEinvoice/ExportEinvoice already carrying both parties -
   // everything else in this function is plain data mapping.
   oInvoice := EinvFactory():createInvoice( oSeller, oBuyer, cInvoiceId, nwinvoices->issuedate )

   oInvoice:setCurrency( AllTrim( nwinvoices->currency ) )
   oInvoice:setBuyerReference( cCustomerId )
   oInvoice:setDeliveryDate( nwinvoices->issuedate )

   // EinvoicePaymentTerms, built with setXXX() instead of a DataObject.
   oPaymentTerms := EinvoicePaymentTerms():new()
   oPaymentTerms:setDueDate( nwinvoices->duedate )
   oInvoice:setPaymentTerms( oPaymentTerms )

   // Northwind Inc.'s own (fictitious) bank account - the BG-16 payment
   // instructions on every demo invoice. EinvoicePaymentMeans, built
   // with setXXX() instead of a DataObject.
   oPaymentMeans := EinvoicePaymentMeans():new()
   oPaymentMeans:setCode( EINV_PAYMEANS_SEPA_CREDIT_TRANSFER )
   oPaymentMeans:setIban( "DE67 5004 0000 0388 5209 00" )
   oPaymentMeans:setBic( "COBADEFFXXX" )
   oPaymentMeans:setAccountName( "Northwind Inc." )
   oInvoice:setPaymentMeans( oPaymentMeans )

   IF nwinvdet->( DbSeek( nInvoiceId ) )
      DO WHILE !nwinvdet->( Eof() ) .AND. nwinvdet->invoiceid == nInvoiceId
         // EinvoiceLineItem, built with setXXX() instead of a DataObject.
         oLineData := EinvoiceLineItem():new()
         oLineData:setName( AllTrim( nwinvdet->itemname ) )
         oLineData:setSellerItemId( AllTrim( Str( nwinvdet->productid ) ) )
         oLineData:setQuantity( nwinvdet->quantity )
         oLineData:setPrice( nwinvdet->netamount / nwinvdet->quantity )
         oInvoice:addLineItem( oLineData )
         nwinvdet->( DbSkip() )
      ENDDO
   ENDIF

   DbCloseAll()

RETURN oInvoice

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
