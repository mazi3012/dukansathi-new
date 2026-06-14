import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/database.dart';
import '../models/cart_item.dart';
import '../models/draft_approval.dart';
import '../models/tax_breakdown.dart';
import 'pdf_file_helper.dart';

enum InvoicePdfTemplate {
  igst,
  cgstSgst,
  nonGst,
  composite,
}

class GeneratedInvoicePdf {
  GeneratedInvoicePdf({
    this.file,
    required this.bytes,
    required this.caption,
    required this.template,
  });

  final dynamic file; // io.File on native, null on web
  final Uint8List bytes;
  final String caption;
  final InvoicePdfTemplate template;
}

class InvoicePdfGenerator {
  static const List<String> _fontCandidates = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    '/opt/flutter/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/Roboto/Roboto-Regular.ttf',
  ];

  static InvoicePdfTemplate resolveTemplate(TaxBreakdown taxBreakdown) {
    if (taxBreakdown.gstMode == 'COMPOSITE') {
      return InvoicePdfTemplate.composite;
    }
    if (taxBreakdown.gstMode == 'UNREGISTERED') {
      return InvoicePdfTemplate.nonGst;
    }
    if (taxBreakdown.igstAmount > 0) {
      return InvoicePdfTemplate.igst;
    }
    return InvoicePdfTemplate.cgstSgst;
  }

  static String templateLabel(InvoicePdfTemplate template) {
    switch (template) {
      case InvoicePdfTemplate.igst:
      case InvoicePdfTemplate.cgstSgst:
        return 'TAX INVOICE';
      case InvoicePdfTemplate.nonGst:
        return 'BILL OF SUPPLY';
      case InvoicePdfTemplate.composite:
        return 'COMPOSITE BILL';
    }
  }

  static Future<GeneratedInvoicePdf> generateApprovedInvoicePdfOffline({
    required DraftApproval approval,
    required String invoiceNumber,
    required String shopName,
    required String shopState,
    required String? gstNumber,
    required String businessType,
    required String customerName,
    required String? customerPhone,
    required Map<String, Map<String, dynamic>> productDetails,
  }) async {
    final template = resolveTemplate(approval.proposedTaxBreakdown);
    final approvedAt = approval.reviewedAt ?? DateTime.now();
    final theme = await _loadTheme();

    final document = pw.Document(theme: theme);
    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28.35), // 10mm margins
        ),
        footer: (context) => _buildFooter(template: template),
        build: (context) => [
          _buildInvoicePage(
            approval: approval,
            shopName: shopName,
            shopState: shopState,
            gstNumber: gstNumber,
            businessType: businessType,
            customerName: customerName,
            customerPhone: customerPhone,
            invoiceNumber: invoiceNumber,
            approvedAt: approvedAt,
            productDetails: productDetails,
            template: template,
          ),
        ],
      ),
    );

    final bytes = await document.save();
    final safeInvoiceNumber = invoiceNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = await savePdfToTemp(bytes, safeInvoiceNumber);

    return GeneratedInvoicePdf(
      file: file,
      bytes: bytes,
      caption: _buildCaption(
        invoiceNumber: invoiceNumber,
        approval: approval,
        template: template,
      ),
      template: template,
    );
  }

  static Future<GeneratedInvoicePdf> generateApprovedInvoicePdf({
    required String approvalId,
    required String invoiceNumber,
  }) async {
    final approval = await _fetchApproval(approvalId);
    final approvalData = await _fetchApprovalData(approvalId);
    final template = resolveTemplate(approval.proposedTaxBreakdown);
    final shop = await _fetchShop(approval.shopId);
    final customerName = approvalData['customer_name'] as String?;
    final customer = approval.customerId == null
        ? null
        : await _fetchCustomer(approval.customerId!);
    final productDetails = await _fetchProductDetails(approval.proposedItems);
    final approvedAt = approval.reviewedAt ?? DateTime.now();
    final theme = await _loadTheme();

    final document = pw.Document(theme: theme);
    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28.35), // 10mm margins
        ),
        footer: (context) => _buildFooter(template: template),
        build: (context) => [
          _buildInvoicePage(
            approval: approval,
            shopName: shop['name'] as String? ?? 'Dukan Sathi',
            shopState: shop['state'] as String? ?? '-',
            gstNumber: shop['gst_registration_number'] as String?,
            businessType: shop['business_type'] as String? ?? 'Retail',
            customerName: approval.customerName?.isNotEmpty == true
              ? approval.customerName!
              : (customerName?.trim().isNotEmpty == true
                  ? customerName!.trim()
                  : customer?['name'] as String? ?? 'Walk-in Customer'),
            customerPhone: ((customer?['phone'] as String?)?.startsWith('AUTO-') ?? false) ? null : customer?['phone'] as String?,
            invoiceNumber: invoiceNumber,
            approvedAt: approvedAt,
            productDetails: productDetails,
            template: template,
          ),
        ],
      ),
    );

    final bytes = await document.save();
    final safeInvoiceNumber = invoiceNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final file = await savePdfToTemp(bytes, safeInvoiceNumber);

    return GeneratedInvoicePdf(
      file: file,
      bytes: bytes,
      caption: _buildCaption(
        invoiceNumber: invoiceNumber,
        approval: approval,
        template: template,
      ),
      template: template,
    );
  }

  static Future<DraftApproval> _fetchApproval(String approvalId) async {
    final approvalRows = await supabase
        .from('draft_approvals')
        .select('approval_id, draft_invoice_id, shop_id, customer_id, created_at, proposed_items, proposed_tax_breakdown, proposed_total, approval_status, reviewed_by, reviewed_at, approval_notes, sale_id, updated_at')
        .eq('approval_id', approvalId)
        .single();
    return DraftApproval.fromJson(Map<String, dynamic>.from(approvalRows as Map));
  }

  static Future<Map<String, dynamic>> _fetchApprovalData(String approvalId) async {
    final approvalRows = await supabase
        .from('draft_approvals')
        .select('approval_id, draft_invoice_id, shop_id, customer_id, created_at, proposed_items, proposed_tax_breakdown, proposed_total, approval_status, reviewed_by, reviewed_at, approval_notes, sale_id, updated_at')
        .eq('approval_id', approvalId)
        .single();
    return Map<String, dynamic>.from(approvalRows as Map);
  }

  static Future<Map<String, dynamic>> _fetchShop(String shopId) async {
    final shopRows = await supabase
        .from('shops')
        .select('id, name, state, gst_registration_number, gst_mode, business_type, created_at')
        .eq('id', shopId)
        .single();
    return Map<String, dynamic>.from(shopRows as Map);
  }

  static Future<Map<String, dynamic>?> _fetchCustomer(String customerId) async {
    try {
      final customerRows = await supabase
          .from('customers')
          .select('id, shop_id, name, phone, current_balance')
          .eq('id', customerId)
          .single();
      return Map<String, dynamic>.from(customerRows as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, Map<String, dynamic>>> _fetchProductDetails(List<CartItem> items) async {
    final details = <String, Map<String, dynamic>>{};
    for (final item in items) {
      try {
        final productRows = await supabase
            .from('products')
            .select('name, hsn_sac_code, gst_rate')
            .eq('id', item.productId)
            .single();
        details[item.productId] = Map<String, dynamic>.from(productRows as Map);
      } catch (_) {
        details[item.productId] = {'name': item.productId, 'hsn_sac_code': null, 'gst_rate': null};
      }
    }
    return details;
  }

  static pw.Widget _buildInvoicePage({
    required DraftApproval approval,
    required String shopName,
    required String shopState,
    required String? gstNumber,
    required String businessType,
    required String customerName,
    required String? customerPhone,
    required String invoiceNumber,
    required DateTime approvedAt,
    required Map<String, Map<String, dynamic>> productDetails,
    required InvoicePdfTemplate template,
  }) {
    final tax = approval.proposedTaxBreakdown;
    final isIgst = template == InvoicePdfTemplate.igst;
    final isNonGst = template == InvoicePdfTemplate.nonGst;
    final title = templateLabel(template);
    
    // Professional Color Palette
    final tealColor = PdfColor.fromInt(0x0D7C66);
    final darkText = PdfColors.grey900;
    final lightGrey = PdfColors.grey100;
    final borderColor = PdfColors.grey300;

    // 1. HEADER
    final headerSection = pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 15),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: tealColor, width: 2)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  shopName.toUpperCase(),
                  style: pw.TextStyle(color: tealColor, fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '$businessType | State: $shopState',
                  style: pw.TextStyle(color: PdfColors.grey700, fontSize: 9),
                ),
                if (gstNumber != null && gstNumber.isNotEmpty)
                  pw.Text(
                    'GSTIN: $gstNumber',
                    style: pw.TextStyle(color: PdfColors.grey700, fontSize: 9),
                  ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(color: tealColor, fontSize: 16, fontWeight: pw.FontWeight.bold, letterSpacing: 1),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Invoice No: $invoiceNumber',
                style: pw.TextStyle(color: darkText, fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Date: ${_formatDateTime(approvedAt)}',
                style: pw.TextStyle(color: PdfColors.grey700, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );

    // 2. INFO GRID
    final infoGrid = pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 15),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Bill To
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: lightGrey, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Billed To:', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  pw.SizedBox(height: 4),
                  pw.Text(customerName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: darkText)),
                  if (customerPhone != null && customerPhone.isNotEmpty)
                    pw.Text('Phone: $customerPhone', style: pw.TextStyle(fontSize: 8, color: darkText)),
                  pw.Text('State (POS): ${approval.customerState ?? shopState}', style: pw.TextStyle(fontSize: 8, color: darkText)),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 15),
          // Invoice Details
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: lightGrey, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Payment Details:', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Text('Status: ', style: pw.TextStyle(fontSize: 9, color: darkText)),
                      _buildStatusBadge(approval.paymentStatus),
                    ]
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text('Approval ID: ${approval.approvalId.split('-').first.toUpperCase()}', style: pw.TextStyle(fontSize: 8, color: darkText)),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // 3. ITEMS TABLE — Indian GST Invoice format
    final useAdjusted = tax.breakdown.isNotEmpty && tax.breakdown.length == approval.proposedItems.length;

    final itemRows = approval.proposedItems.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final item = entry.value;
      final details = productDetails[item.productId];
      final itemName = details?['name'] as String? ?? item.productName ?? item.productId;
      final hsn = details?['hsn_sac_code'] as String? ?? '-';
      final gstRate = item.gstRate;
      final rateStr = gstRate == gstRate.roundToDouble() ? '${gstRate.toInt()}%' : '${gstRate.toStringAsFixed(1)}%';
      
      final double lineTotal = item.quantity * item.unitPrice;
      
      double taxableValue;
      double taxAmount;
      double totalWithTax;
      
      if (useAdjusted) {
        final br = tax.breakdown[entry.key];
        final cgst = (br['cgst'] as num?)?.toDouble() ?? 0.0;
        final sgst = (br['sgst'] as num?)?.toDouble() ?? 0.0;
        final igst = (br['igst'] as num?)?.toDouble() ?? 0.0;
        
        taxAmount = cgst + sgst + igst;
        totalWithTax = (br['totalWithTax'] as num?)?.toDouble() ?? (lineTotal + taxAmount);
        taxableValue = totalWithTax - taxAmount;
      } else {
        taxableValue = lineTotal;
        taxAmount = taxableValue * (gstRate / 100);
        totalWithTax = taxableValue + taxAmount;
      }

      return [
        index.toString(),
        itemName,
        hsn,
        item.quantity.toString(),
        _money(item.unitPrice),
        _money(taxableValue),
        rateStr,
        _money(taxAmount),
        _money(totalWithTax),
      ];
    }).toList();

    final itemsTable = pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 7),
      cellStyle: pw.TextStyle(fontSize: 7, color: darkText),
      headerDecoration: pw.BoxDecoration(color: tealColor),
      border: pw.TableBorder.all(color: borderColor, width: 0.5),
      cellHeight: 22,
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.center,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.center,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
      },
      columnWidths: const {
        0: pw.FixedColumnWidth(20),   // #
        1: pw.FlexColumnWidth(3.0),   // Item Description
        2: pw.FixedColumnWidth(45),   // HSN/SAC
        3: pw.FixedColumnWidth(25),   // Qty
        4: pw.FixedColumnWidth(55),   // Rate
        5: pw.FixedColumnWidth(60),   // Taxable Value
        6: pw.FixedColumnWidth(30),   // GST %
        7: pw.FixedColumnWidth(55),   // Tax Amt
        8: pw.FixedColumnWidth(65),   // Total
      },
      headers: const ['#', 'Item Description', 'HSN', 'Qty', 'Rate', 'Taxable', 'GST', 'Tax Amt', 'Total'],
      data: itemRows,
    );

    // 4. BILLING SUMMARY
    final gstSummaryRows = tax.rateWiseSummary.map((entry) {
      final rate = (entry['rate'] as num).toDouble();
      final rateStr = rate == rate.roundToDouble() ? '${rate.toInt()}%' : '${rate.toStringAsFixed(1)}%';
      final taxableAmt = _money((entry['taxableAmount'] as num).toDouble());
      final totalTax = _money((entry['totalTax'] as num).toDouble());
      if (isIgst) {
        final igst = _money((entry['igst'] as num).toDouble());
        return [rateStr, taxableAmt, igst, totalTax];
      } else {
        final cgst = _money((entry['cgst'] as num).toDouble());
        final sgst = _money((entry['sgst'] as num).toDouble());
        return [rateStr, taxableAmt, cgst, sgst, totalTax];
      }
    }).toList();

    final summarySection = pw.Container(
      margin: const pw.EdgeInsets.only(top: 15),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Left Side: GST Summary
          pw.Expanded(
            flex: 5,
            child: (gstSummaryRows.isNotEmpty && !isNonGst && template != InvoicePdfTemplate.composite)
              ? pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('GST Breakup', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: tealColor)),
                    pw.SizedBox(height: 4),
                    pw.TableHelper.fromTextArray(
                      headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 6),
                      cellStyle: pw.TextStyle(fontSize: 6, color: darkText),
                      headerDecoration: pw.BoxDecoration(color: tealColor),
                      border: pw.TableBorder.all(color: borderColor, width: 0.5),
                      cellHeight: 16,
                      cellAlignments: {
                        0: pw.Alignment.centerLeft,
                        1: pw.Alignment.centerRight,
                        2: pw.Alignment.centerRight,
                        3: pw.Alignment.centerRight,
                        4: pw.Alignment.centerRight,
                      },
                      columnWidths: isIgst
                        ? {0: const pw.FixedColumnWidth(35), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1)}
                        : {0: const pw.FixedColumnWidth(30), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1), 4: const pw.FlexColumnWidth(1)},
                      headers: isIgst
                        ? const ['GST', 'Taxable', 'IGST', 'Total Tax']
                        : const ['GST', 'Taxable', 'CGST', 'SGST', 'Total Tax'],
                      data: gstSummaryRows,
                    ),
                  ],
                )
              : pw.SizedBox(),
          ),
          pw.SizedBox(width: 20),
          // Right Side: Totals Block
          pw.Expanded(
            flex: 4,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: lightGrey,
                borderRadius: pw.BorderRadius.circular(4),
                border: pw.Border.all(color: borderColor),
              ),
              child: pw.Column(
                children: [
                  if (approval.discountAmount != null && approval.discountAmount! > 0) ...[
                    _summaryRow('Subtotal', _money(approval.subtotalBeforeDiscount ?? tax.subtotal)),
                    _summaryRow(
                      approval.discountType == 'PERCENT' && approval.discountValue != null
                          ? 'Discount (${approval.discountValue!.toStringAsFixed(1)}%)'
                          : 'Discount',
                      '-${_money(approval.discountAmount!)}',
                      color: PdfColors.green700,
                    ),
                  ],
                  _summaryRow('Taxable Value', _money(approval.subtotalAfterDiscount ?? tax.subtotal)),
                  pw.SizedBox(height: 4),
                  // Rate-wise GST breakdown
                  if (tax.rateWiseSummary.isNotEmpty)
                    ...tax.rateWiseSummary.where((e) => (e['rate'] as num).toDouble() > 0).expand((entry) {
                      final rate = (entry['rate'] as num).toDouble();
                      final rateStr = rate == rate.roundToDouble() ? rate.toInt().toString() : rate.toStringAsFixed(1);
                      if (isIgst) {
                        final igst = (entry['igst'] as num).toDouble();
                        return [_summaryRow('IGST ($rateStr%)', _money(igst))];
                      } else {
                        final cgst = (entry['cgst'] as num).toDouble();
                        final sgst = (entry['sgst'] as num).toDouble();
                        final halfRate = rate / 2;
                        final halfRateStr = halfRate == halfRate.roundToDouble() ? halfRate.toInt().toString() : halfRate.toStringAsFixed(1);
                        return [
                          _summaryRow('CGST ($halfRateStr%)', _money(cgst)),
                          _summaryRow('SGST ($halfRateStr%)', _money(sgst)),
                        ];
                      }
                    })
                  else ...[
                    if (isIgst) _summaryRow('IGST', _money(tax.igstAmount)),
                    if (!isIgst && !isNonGst) ...[
                      _summaryRow('CGST', _money(tax.cgstAmount)),
                      _summaryRow('SGST', _money(tax.sgstAmount)),
                    ],
                  ],
                  pw.Divider(color: borderColor, thickness: 1),
                  pw.SizedBox(height: 4),
                  _summaryRow('Grand Total', _money(approval.proposedTotal), isBold: true, fontSize: 12, color: tealColor),
                  pw.SizedBox(height: 8),
                  // Always show payment breakdown when status is PARTIAL or PAID
                  if (approval.paymentStatus == 'PARTIAL') ...[
                    _summaryRow('Amount Paid', _money(approval.amountPaid), color: PdfColors.green700),
                    _summaryRow('Balance Due', _money(approval.dueAmount > 0 ? approval.dueAmount : approval.proposedTotal - approval.amountPaid), color: PdfColors.red700, isBold: true),
                  ] else if (approval.paymentStatus == 'PAID') ...[
                    _summaryRow('Amount Paid', _money(approval.proposedTotal), color: PdfColors.green700),
                  ] else ...[
                    // UNPAID — show full amount as due
                    _summaryRow('Balance Due', _money(approval.proposedTotal), color: PdfColors.red700, isBold: true),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        headerSection,
        infoGrid,
        itemsTable,
        summarySection,
      ],
    );
  }

  static pw.Widget _buildFooter({required InvoicePdfTemplate template}) {
    final borderColor = PdfColors.grey300;
    final darkText = PdfColors.grey900;
    final isIgst = template == InvoicePdfTemplate.igst;
    
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 20),
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: borderColor)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                isIgst ? 'Inter-state transaction (IGST applied). Reverse Charge: Not Applicable' : 'Intra-state transaction (CGST+SGST applied). Reverse Charge: Not Applicable',
                style: pw.TextStyle(fontSize: 7, color: darkText),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'This is a computer-generated invoice and does not require a physical signature.',
                style: pw.TextStyle(color: PdfColors.grey500, fontSize: 7, fontStyle: pw.FontStyle.italic),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(height: 30),
              pw.Container(width: 120, height: 1, color: darkText),
              pw.SizedBox(height: 4),
              pw.Text('Authorized Signatory', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: darkText)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildStatusBadge(String status) {
    final color = status == 'PAID' ? PdfColors.green600 : (status == 'PARTIAL' ? PdfColors.orange600 : PdfColors.red600);
    final bgColor = status == 'PAID' ? PdfColors.green50 : (status == 'PARTIAL' ? PdfColors.orange50 : PdfColors.red50);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: color, width: 0.5),
      ),
      child: pw.Text(
        status,
        style: pw.TextStyle(color: color, fontSize: 7, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _summaryRow(String label, String value, {bool isBold = false, double fontSize = 9, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? PdfColors.grey800)),
          pw.Text(value, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? PdfColors.grey900)),
        ],
      ),
    );
  }

  static String _taxSummaryText(TaxBreakdown tax, InvoicePdfTemplate template) {
    switch (template) {
      case InvoicePdfTemplate.igst:
        return 'Inter-state sale: IGST is applied at the saved tax rate.\nSubtotal: ${_money(tax.subtotal)}\nIGST: ${_money(tax.igstAmount)}\nGrand Total: ${_money(tax.totalAmount)}';
      case InvoicePdfTemplate.cgstSgst:
        return 'Intra-state sale: CGST and SGST are applied separately.\nSubtotal: ${_money(tax.subtotal)}\nCGST: ${_money(tax.cgstAmount)}\nSGST: ${_money(tax.sgstAmount)}\nGrand Total: ${_money(tax.totalAmount)}';
      case InvoicePdfTemplate.nonGst:
        return 'GST is not applicable for this saved invoice.\nSubtotal: ${_money(tax.subtotal)}\nGrand Total: ${_money(tax.totalAmount)}';
      case InvoicePdfTemplate.composite:
        return 'Composite GST invoice.\nSubtotal: ${_money(tax.subtotal)}\nComposite GST: ${_money(tax.totalAmount - tax.subtotal)}\nGrand Total: ${_money(tax.totalAmount)}';
    }
  }

  static String _buildCaption({
    required String invoiceNumber,
    required DraftApproval approval,
    required InvoicePdfTemplate template,
  }) {
    return [
      'Invoice $invoiceNumber finalized',
      'Approval ID: ${approval.approvalId}',
      'Template: ${templateLabel(template)}',
      'Total: ${_money(approval.proposedTotal)}',
    ].join('\n');
  }

  static Future<pw.ThemeData> _loadTheme() async {
    // Force Helvetica as per user requirement "Helvetica only"
    return pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    return '$day-$month-$year';
  }

  static String _money(double value) {
    return 'Rs. ${value.toStringAsFixed(2)}';
  }
}