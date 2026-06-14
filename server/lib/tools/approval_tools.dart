import 'package:uuid/uuid.dart';
import '../core/database.dart';
import '../shared/models/cart_item.dart';
import '../shared/services/gst_calculator.dart';
import '../shared/models/shop_config.dart';
import 'inventory_tools.dart';

double _roundToTwoDecimals(double value) => (value * 100).round() / 100;

String? _normalizeCustomerName(dynamic value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized.replaceAll(RegExp(r'\s+'), ' ');
}

String _normalizePaymentStatus(dynamic value, double amountPaid, double totalAmount) {
  final normalized = value?.toString().trim().toUpperCase();
  if (normalized == null || normalized.isEmpty) {
    if (amountPaid <= 0) return 'UNPAID';
    if (amountPaid >= totalAmount) return 'PAID';
    return 'PARTIAL';
  }
  if (normalized == 'PAID' || normalized == 'PARTIAL' || normalized == 'UNPAID') {
    return normalized;
  }
  throw StateError('Invalid payment status in draft approval.');
}

/// Computes invoice-level discount amounts WITHOUT mutating item unit prices.
/// Per Section 15(3)(a) CGST Act, the discount is applied to the aggregate
/// subtotal to establish taxable value. Items are returned unchanged.
Map<String, dynamic> _applyDiscountToItems({
  required List<CartItem> items,
  required String? discountType,
  required double? discountValue,
}) {
  final subtotal = _roundToTwoDecimals(
    items.fold<double>(0.0, (sum, item) => sum + (item.unitPrice * item.quantity)),
  );

  if (subtotal <= 0) {
    return {
      'subtotalBeforeDiscount': 0.0,
      'discountAmount': 0.0,
      'subtotalAfterDiscount': 0.0,
      'items': items, // original items unchanged
    };
  }

  var discountAmount = 0.0;
  if (discountType != null && discountValue != null) {
    if (discountType == 'PERCENT') {
      if (discountValue < 0 || discountValue > 100) {
        throw StateError('discountValue must be between 0 and 100 for percent discounts.');
      }
      discountAmount = subtotal * (discountValue / 100.0);
    } else {
      if (discountValue < 0) {
        throw StateError('discountValue must be non-negative for fixed amount discounts.');
      }
      discountAmount = discountValue;
    }
  }

  if (discountAmount > subtotal) {
    throw StateError('Discount cannot be greater than subtotal.');
  }

  final subtotalAfterDiscount = _roundToTwoDecimals(subtotal - discountAmount);

  return {
    'subtotalBeforeDiscount': subtotal,
    'discountAmount': _roundToTwoDecimals(discountAmount),
    'subtotalAfterDiscount': subtotalAfterDiscount,
    'items': items, // original items unchanged — no unit price mutation
  };
}

Future<void> _deductInventoryStock({
  required String shopId,
  required List<CartItem> items,
}) async {
  final productIds = items.map((item) => item.productId).toSet().toList();
  if (productIds.isEmpty) {
    return;
  }

  final productRows = await supabase
      .from('products')
      .select('id, name, stock_quantity')
      .eq('shop_id', shopId)
      .inFilter('id', productIds);

  final stockById = <String, Map<String, dynamic>>{};
  for (final row in productRows as List<dynamic>) {
    final data = Map<String, dynamic>.from(row as Map);
    final productId = data['id']?.toString();
    if (productId != null) {
      stockById[productId] = data;
    }
  }

  final updates = <Map<String, dynamic>>[];
  for (final item in items) {
    final productData = stockById[item.productId];
    if (productData == null) {
      throw StateError('Product not found in inventory.');
    }
    final currentStock = (productData['stock_quantity'] as num?)?.toInt() ?? 0;
    final productName = productData['name'] as String? ?? 'Unknown Product';
    
    if (currentStock < item.quantity) {
      throw StateError('Insufficient stock for "$productName". Available: $currentStock, required: ${item.quantity}. Please update inventory or edit the draft.');
    }

    updates.add({
      'id': item.productId,
      'shop_id': shopId,
      'stock_quantity': currentStock - item.quantity,
    });
  }

  // Update each product's stock using individual UPDATE (not upsert — no INSERT needed)
  for (final update in updates) {
    await supabase
        .from('products')
        .update({'stock_quantity': update['stock_quantity']})
        .eq('id', update['id'] as String)
        .eq('shop_id', shopId);
  }
}

Future<void> _updateCustomerBalance({
  required String shopId,
  required String customerId,
  required double dueAmount,
}) async {
  if (dueAmount <= 0) {
    return;
  }

  final customerRows = await supabase
      .from('customers')
      .select('id, current_balance')
      .eq('shop_id', shopId)
      .eq('id', customerId)
      .single();

  final customerData = Map<String, dynamic>.from(customerRows as Map);
  final currentBalance = (customerData['current_balance'] as num?)?.toDouble() ?? 0.0;

  await supabase.from('customers').update({
    'current_balance': _roundToTwoDecimals(currentBalance + dueAmount),
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('shop_id', shopId).eq('id', customerId);
}

Future<String?> _ensureCustomerRecord({
  required String shopId,
  required String? existingCustomerId,
  required String? customerName,
}) async {
  if (existingCustomerId != null && existingCustomerId.isNotEmpty) {
    return existingCustomerId;
  }

  final normalizedName = _normalizeCustomerName(customerName);
  if (normalizedName == null || normalizedName.toLowerCase() == 'walk-in customer') {
    return null;
  }

  try {
    final existingByName = await supabase
        .from('customers')
        .select('id, name')
        .eq('shop_id', shopId)
        .ilike('name', normalizedName)
        .maybeSingle();

    if (existingByName != null) {
      final customerData = Map<String, dynamic>.from(existingByName as Map);
      final customerId = customerData['id']?.toString();
      if (customerId != null && customerId.isNotEmpty) {
        return customerId;
      }
    }
  } catch (_) {
    // Continue to insert fallback customer.
  }

  final generatedPhone = 'AUTO-${DateTime.now().millisecondsSinceEpoch}-${const Uuid().v4().substring(0, 6)}';
  final insertRows = await supabase
      .from('customers')
      .insert({
        'shop_id': shopId,
        'name': normalizedName,
        'phone': generatedPhone,
        'current_balance': 0,
      })
      .select('id')
      .single();

  return (insertRows as Map)['id']?.toString();
}

Future<Map<String, dynamic>> updateDraftPaymentStatus({
  required String approvalId,
  required String paymentStatus,
  double? amountPaid,
}) async {
  try {
    final approvalRows = await supabase
        .from('draft_approvals')
        .select('approval_id, draft_invoice_id, shop_id, customer_id, customer_name, customer_state, proposed_items, proposed_tax_breakdown, proposed_total, approval_status, reviewed_by, reviewed_at, approval_notes, sale_id, created_at, updated_at, original_items, payment_status, amount_paid, due_amount, discount_type, discount_value, discount_amount, subtotal_before_discount, subtotal_after_discount')
        .eq('approval_id', approvalId)
        .eq('approval_status', 'PENDING')
        .single();

    final approvalData = Map<String, dynamic>.from(approvalRows as Map);
    final proposedTotal = (approvalData['proposed_total'] as num?)?.toDouble() ?? 0.0;
    final normalized = paymentStatus.toUpperCase();

    double resolvedAmountPaid;
    double dueAmount;
    if (normalized == 'PAID') {
      resolvedAmountPaid = proposedTotal;
      dueAmount = 0.0;
    } else if (normalized == 'PARTIAL') {
      resolvedAmountPaid = amountPaid ?? (approvalData['amount_paid'] as num?)?.toDouble() ?? 0.0;
      if (resolvedAmountPaid < 0) {
        throw StateError('amountPaid cannot be negative.');
      }
      if (resolvedAmountPaid > proposedTotal) {
        throw StateError('amountPaid cannot exceed the invoice total.');
      }
      dueAmount = _roundToTwoDecimals(proposedTotal - resolvedAmountPaid);
    } else {
      resolvedAmountPaid = 0.0;
      dueAmount = proposedTotal;
    }

    await supabase.from('draft_approvals').update({
      'payment_status': normalized,
      'amount_paid': resolvedAmountPaid,
      'due_amount': dueAmount,
    }).eq('approval_id', approvalId);

    return {
      'success': true,
      'approvalId': approvalId,
      'paymentStatus': normalized,
      'amountPaid': resolvedAmountPaid,
      'dueAmount': dueAmount,
    };
  } catch (e) {
    return {
      'success': false,
      'error': 'Failed to update payment status: $e',
    };
  }
}

Future<Map<String, dynamic>> updateDraftItem({
  required String approvalId,
  required String productId,
  required int newQuantity,
  double? newUnitPrice,
}) async {
  try {
    final approvalRows = await supabase
        .from('draft_approvals')
        .select('approval_id, draft_invoice_id, shop_id, customer_id, customer_name, customer_state, proposed_items, proposed_tax_breakdown, proposed_total, approval_status, reviewed_by, reviewed_at, approval_notes, sale_id, created_at, updated_at, original_items, payment_status, amount_paid, due_amount, discount_type, discount_value, discount_amount, subtotal_before_discount, subtotal_after_discount')
        .eq('approval_id', approvalId)
        .eq('approval_status', 'PENDING')
        .single();

    final approvalData = Map<String, dynamic>.from(approvalRows as Map);
    final shopId = (approvalData['shop_id'] ?? '').toString();
    final customerState = approvalData['customer_state']?.toString();
    final discountType = approvalData['discount_type']?.toString();
    final discountValue = (approvalData['discount_value'] as num?)?.toDouble();

    final originalItemsJson = (approvalData['original_items'] as List<dynamic>? ?? approvalData['proposed_items'] as List<dynamic>?) ?? const [];
    
    bool itemFound = false;
    final originalItems = originalItemsJson.map((itemJson) {
      final json = Map<String, dynamic>.from(itemJson as Map);
      final rawGstRate = (json['gstRate'] as num?)?.toDouble() ?? 0.0;
      final currentProductId = (json['productId'] ?? '').toString();
      
      if (currentProductId == productId) {
        itemFound = true;
        return CartItem(
          productId: currentProductId,
          productName: json['productName']?.toString(),
          quantity: newQuantity,
          unitPrice: newUnitPrice ?? (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
          gstRate: rawGstRate > 0 ? rawGstRate : 18.0,
        );
      }
      
      return CartItem(
        productId: currentProductId,
        productName: json['productName']?.toString(),
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
        gstRate: rawGstRate > 0 ? rawGstRate : 18.0,
      );
    }).toList();

    if (!itemFound) {
      throw StateError('Product not found in draft items.');
    }

    final billingAdjustments = _applyDiscountToItems(
      items: originalItems,
      discountType: discountType,
      discountValue: discountValue,
    );
    // Items are returned unchanged (original unit prices preserved)
    final subtotalBeforeDiscount = billingAdjustments['subtotalBeforeDiscount'] as double;
    final discountAmount = billingAdjustments['discountAmount'] as double;
    final subtotalAfterDiscount = billingAdjustments['subtotalAfterDiscount'] as double;

    final shopRows = await supabase
        .from('shops')
        .select('id, state, gst_registration_number, gst_mode, business_type, created_at')
        .eq('id', shopId)
        .single();

    final shopData = Map<String, dynamic>.from(shopRows as Map);
    final gstModeStr = shopData['gst_mode'] as String? ?? 'REGISTERED';
    final gstMode = GSTMode.values.firstWhere(
      (e) => e.name == gstModeStr.toLowerCase(),
      orElse: () => GSTMode.registered,
    );

    final shopConfig = ShopConfig(
      shopId: shopId,
      state: shopData['state'] as String,
      gstRegistrationNumber: shopData['gst_registration_number'] as String?,
      gstMode: gstMode,
      businessType: shopData['business_type'] as String? ?? 'Retail',
      createdAt: DateTime.parse(shopData['created_at'] as String),
    );

    final taxBreakdown = GSTCalculator.calculateTax(
      items: originalItems,
      shopConfig: shopConfig,
      customerState: customerState,
      invoiceDiscount: discountAmount,
    );

    final paymentStatus = _normalizePaymentStatus(
      approvalData['payment_status'],
      (approvalData['amount_paid'] as num?)?.toDouble() ?? 0.0,
      taxBreakdown.totalAmount,
    );

    final amountPaid = paymentStatus == 'PAID'
        ? taxBreakdown.totalAmount
        : paymentStatus == 'PARTIAL'
            ? (_roundToTwoDecimals((approvalData['amount_paid'] as num?)?.toDouble() ?? 0.0)).clamp(0.0, taxBreakdown.totalAmount)
            : 0.0;
    final dueAmount = _roundToTwoDecimals(taxBreakdown.totalAmount - amountPaid);

    await supabase.from('draft_approvals').update({
      'original_items': originalItems.map((item) => item.toJson()).toList(),
      'proposed_items': originalItems.map((item) => item.toJson()).toList(),
      'proposed_tax_breakdown': {
        'subtotal': taxBreakdown.subtotal,
        'cgst_amount': taxBreakdown.cgstAmount,
        'sgst_amount': taxBreakdown.sgstAmount,
        'igst_amount': taxBreakdown.igstAmount,
        'gst_mode': taxBreakdown.gstMode,
        'applicable_state': taxBreakdown.applicableState,
        'tax_slab': taxBreakdown.taxSlab,
        'total_amount': taxBreakdown.totalAmount,
        'breakdown': taxBreakdown.breakdown,
        'rate_wise_summary': taxBreakdown.rateWiseSummary,
      },
      'proposed_total': taxBreakdown.totalAmount,
      'subtotal_before_discount': subtotalBeforeDiscount,
      'subtotal_after_discount': subtotalAfterDiscount,
      'discount_amount': discountAmount,
      'payment_status': paymentStatus,
      'amount_paid': amountPaid,
      'due_amount': dueAmount,
    }).eq('approval_id', approvalId);

    return {
      'success': true,
      'approvalId': approvalId,
      'paymentStatus': paymentStatus,
      'amountPaid': amountPaid,
      'dueAmount': dueAmount,
    };
  } catch (e) {
    return {
      'success': false,
      'error': 'Failed to update item: $e',
    };
  }
}

Future<Map<String, dynamic>> updateDraftDiscount({
  required String approvalId,
  required String discountType,
  required double discountValue,
}) async {
  try {
    final approvalRows = await supabase
        .from('draft_approvals')
        .select('approval_id, draft_invoice_id, shop_id, customer_id, customer_name, customer_state, proposed_items, proposed_tax_breakdown, proposed_total, approval_status, reviewed_by, reviewed_at, approval_notes, sale_id, created_at, updated_at, original_items, payment_status, amount_paid, due_amount, discount_type, discount_value, discount_amount, subtotal_before_discount, subtotal_after_discount')
        .eq('approval_id', approvalId)
        .eq('approval_status', 'PENDING')
        .single();

    final approvalData = Map<String, dynamic>.from(approvalRows as Map);
    final shopId = (approvalData['shop_id'] ?? '').toString();
    final customerState = approvalData['customer_state']?.toString();
    final originalItemsJson = (approvalData['original_items'] as List<dynamic>? ?? approvalData['proposed_items'] as List<dynamic>?) ?? const [];
    final originalItems = originalItemsJson.map((itemJson) {
      final json = Map<String, dynamic>.from(itemJson as Map);
      final rawGstRate = (json['gstRate'] as num?)?.toDouble() ?? 0.0;
      return CartItem(
        productId: (json['productId'] ?? '').toString(),
        productName: json['productName']?.toString(),
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
        gstRate: rawGstRate > 0 ? rawGstRate : 18.0,
      );
    }).toList();

    if (originalItems.isEmpty) {
      throw StateError('Draft has no items to discount.');
    }

    final billingAdjustments = _applyDiscountToItems(
      items: originalItems,
      discountType: discountType,
      discountValue: discountValue,
    );
    // Items are returned unchanged (original unit prices preserved)
    final subtotalBeforeDiscount = billingAdjustments['subtotalBeforeDiscount'] as double;
    final discountAmount = billingAdjustments['discountAmount'] as double;
    final subtotalAfterDiscount = billingAdjustments['subtotalAfterDiscount'] as double;

    final shopRows = await supabase
        .from('shops')
        .select('id, state, gst_registration_number, gst_mode, business_type, created_at')
        .eq('id', shopId)
        .single();

    final shopData = Map<String, dynamic>.from(shopRows as Map);
    final gstModeStr = shopData['gst_mode'] as String? ?? 'REGISTERED';
    final gstMode = GSTMode.values.firstWhere(
      (e) => e.name == gstModeStr.toLowerCase(),
      orElse: () => GSTMode.registered,
    );

    final shopConfig = ShopConfig(
      shopId: shopId,
      state: shopData['state'] as String,
      gstRegistrationNumber: shopData['gst_registration_number'] as String?,
      gstMode: gstMode,
      businessType: shopData['business_type'] as String? ?? 'Retail',
      createdAt: DateTime.parse(shopData['created_at'] as String),
    );

    final taxBreakdown = GSTCalculator.calculateTax(
      items: originalItems,
      shopConfig: shopConfig,
      customerState: customerState,
      invoiceDiscount: discountAmount,
    );

    final paymentStatus = _normalizePaymentStatus(
      approvalData['payment_status'],
      (approvalData['amount_paid'] as num?)?.toDouble() ?? 0.0,
      taxBreakdown.totalAmount,
    );

    final amountPaid = paymentStatus == 'PAID'
        ? taxBreakdown.totalAmount
        : paymentStatus == 'PARTIAL'
            ? (_roundToTwoDecimals((approvalData['amount_paid'] as num?)?.toDouble() ?? 0.0)).clamp(0.0, taxBreakdown.totalAmount)
            : 0.0;
    final dueAmount = _roundToTwoDecimals(taxBreakdown.totalAmount - amountPaid);

    await supabase.from('draft_approvals').update({
      'proposed_items': originalItems.map((item) => item.toJson()).toList(),
      'proposed_tax_breakdown': {
        'subtotal': taxBreakdown.subtotal,
        'cgst_amount': taxBreakdown.cgstAmount,
        'sgst_amount': taxBreakdown.sgstAmount,
        'igst_amount': taxBreakdown.igstAmount,
        'gst_mode': taxBreakdown.gstMode,
        'applicable_state': taxBreakdown.applicableState,
        'tax_slab': taxBreakdown.taxSlab,
        'total_amount': taxBreakdown.totalAmount,
        'breakdown': taxBreakdown.breakdown,
        'rate_wise_summary': taxBreakdown.rateWiseSummary,
      },
      'proposed_total': taxBreakdown.totalAmount,
      'subtotal_before_discount': subtotalBeforeDiscount,
      'subtotal_after_discount': subtotalAfterDiscount,
      'discount_type': discountType,
      'discount_value': discountValue,
      'discount_amount': discountAmount,
      'payment_status': paymentStatus,
      'amount_paid': amountPaid,
      'due_amount': dueAmount,
    }).eq('approval_id', approvalId);

    return {
      'success': true,
      'approvalId': approvalId,
      'discountType': discountType,
      'discountValue': discountValue,
      'discountAmount': discountAmount,
      'subtotalBeforeDiscount': subtotalBeforeDiscount,
      'subtotalAfterDiscount': subtotalAfterDiscount,
      'paymentStatus': paymentStatus,
      'amountPaid': amountPaid,
      'dueAmount': dueAmount,
    };
  } catch (e) {
    return {
      'success': false,
      'error': 'Failed to update discount: $e',
    };
  }
}

/// Approve a pending draft invoice and create Sale + DraftInvoice records
Future<Map<String, dynamic>> approveDraftInvoice({
  required String approvalId,
  required String reviewedBy,
}) async {
  try {
    // Fetch the pending draft approval
    final approvalRows = await supabase
        .from('draft_approvals')
        .select('approval_id, draft_invoice_id, shop_id, customer_id, customer_name, customer_state, proposed_items, proposed_tax_breakdown, proposed_total, approval_status, reviewed_by, reviewed_at, approval_notes, sale_id, created_at, updated_at, original_items, payment_status, amount_paid, due_amount, discount_type, discount_value, discount_amount, subtotal_before_discount, subtotal_after_discount')
        .eq('approval_id', approvalId)
        .eq('approval_status', 'PENDING')
        .single();

    final approvalData = Map<String, dynamic>.from(approvalRows as Map);

    final shopId = approvalData['shop_id'] as String;
    final customerId = approvalData['customer_id'] as String?;
    final customerName = approvalData['customer_name'] as String?;
    final customerState = approvalData['customer_state'] as String?;
    final proposedItems = approvalData['proposed_items'] as List;
    final proposedTotal = approvalData['proposed_total'] as num;
    final taxBreakdown = approvalData['proposed_tax_breakdown'] as Map<String, dynamic>;
    final subtotalBeforeDiscount = (approvalData['subtotal_before_discount'] as num?)?.toDouble() ?? proposedTotal.toDouble();
    final subtotalAfterDiscount = (approvalData['subtotal_after_discount'] as num?)?.toDouble() ?? proposedTotal.toDouble();
    final discountType = approvalData['discount_type'] as String?;
    final discountValue = (approvalData['discount_value'] as num?)?.toDouble();
    final discountAmount = (approvalData['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final amountPaidDraft = (approvalData['amount_paid'] as num?)?.toDouble() ?? 0.0;

    final items = proposedItems.map((itemJson) {
      final json = Map<String, dynamic>.from(itemJson as Map);
      final rawGstRate = (json['gstRate'] as num?)?.toDouble() ?? 0.0;
      return CartItem(
        productId: json['productId'] as String,
        productName: json['productName']?.toString(),
        quantity: json['quantity'] as int,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        gstRate: rawGstRate > 0 ? rawGstRate : 18.0,
      );
    }).toList();

    final resolvedCustomerId = await _ensureCustomerRecord(
      shopId: shopId,
      existingCustomerId: customerId,
      customerName: customerName,
    );

    final paymentStatus = _normalizePaymentStatus(
      approvalData['payment_status'],
      amountPaidDraft,
      proposedTotal.toDouble(),
    );
    final amountPaid = paymentStatus == 'PAID'
        ? proposedTotal.toDouble()
        : paymentStatus == 'PARTIAL'
            ? amountPaidDraft
            : 0.0;

    // Guard: PARTIAL must have a positive amountPaid
    if (paymentStatus == 'PARTIAL' && amountPaid <= 0) {
      return {
        'success': false,
        'error': 'Please enter the paid amount before approving a partial payment invoice.',
      };
    }

    final dueAmount = _roundToTwoDecimals(proposedTotal.toDouble() - amountPaid);

    await _deductInventoryStock(shopId: shopId, items: items);

    // Create draft_invoices record
    final draftInvoiceResponse = await supabase
        .from('draft_invoices')
        .insert({
          'shop_id': shopId,
          'customer_id': resolvedCustomerId,
          'customer_name': customerName,
          'items': items.map((item) => item.toJson()).toList(),
          'total_amount': proposedTotal,
          'tax_breakdown': taxBreakdown,
          'status': 'approved',
          'draft_approval_id': approvalId,
        })
        .select('id')
        .single();

    final draftInvoiceId = draftInvoiceResponse['id'] as String;

    // Create Sale record with UUID id and human-readable invoice number
    final saleId = const Uuid().v4();
    final invoiceNumber = 'INV-${approvalId.substring(0, 13).replaceAll('-', '').toUpperCase()}';
    await supabase.from('sales').insert({
      'id': saleId,
      'invoice_number': invoiceNumber,
      'shop_id': shopId,
      'invoice_id': draftInvoiceId,
      'customer_id': resolvedCustomerId,
      'customer_name': customerName,
      'amount': proposedTotal,
      'amount_paid': amountPaid,
      'due_amount': dueAmount,
      'payment_status': paymentStatus,
      'discount_type': discountType,
      'discount_value': discountValue,
      'discount_amount': discountAmount,
      'subtotal_before_discount': subtotalBeforeDiscount,
      'subtotal_after_discount': subtotalAfterDiscount,
      'customer_state': customerState,
      'timestamp': DateTime.now().toIso8601String(),
      'payment_method': 'pending',
      'status': 'approved',
    });

    if (resolvedCustomerId != null) {
      await _updateCustomerBalance(
        shopId: shopId,
        customerId: resolvedCustomerId,
        dueAmount: dueAmount,
      );
    }

    // Update draft_approval status
    await supabase
        .from('draft_approvals')
        .update({
          'approval_status': 'APPROVED',
          'reviewed_by': reviewedBy,
          'reviewed_at': DateTime.now().toIso8601String(),
          'draft_invoice_id': draftInvoiceId,
          'sale_id': saleId,
          'payment_status': paymentStatus,
          'amount_paid': amountPaid,
          'due_amount': dueAmount,
        })
        .eq('approval_id', approvalId);

    return {
      'success': true,
      'approvalId': approvalId,
      'saleId': saleId,
      'invoiceNumber': invoiceNumber,
      'draftInvoiceId': draftInvoiceId,
      'totalAmount': proposedTotal,
      'amountPaid': amountPaid,
      'dueAmount': dueAmount,
      'paymentStatus': paymentStatus,
      'message': '✅ *Invoice Approved!*\n\n🧾 `$invoiceNumber`\n💰 Total: ₹${proposedTotal.toStringAsFixed(2)}\n\n_Saved to records._',
    };
  } catch (e) {
    return {
      'success': false,
      'error': 'Failed to approve draft: $e',
    };
  }
}

/// Reject a pending draft invoice (no Sale created)
Future<Map<String, dynamic>> rejectDraftInvoice({
  required String approvalId,
  required String reviewedBy,
  required String rejectionReason,
}) async {
  try {
    await supabase
        .from('draft_approvals')
        .update({
          'approval_status': 'REJECTED',
          'reviewed_by': reviewedBy,
          'reviewed_at': DateTime.now().toIso8601String(),
          'approval_notes': rejectionReason,
        })
        .eq('approval_id', approvalId);

    return {
      'success': true,
      'approvalId': approvalId,
      'message': '❌ *Invoice Rejected*\n\nReason: $rejectionReason\n\n_The draft has been discarded._',
    };
  } catch (e) {
    return {
      'success': false,
      'error': 'Failed to reject draft: $e',
    };
  }
}

/// Switch an existing PENDING draft between CGST/SGST and IGST.
/// Persists the synthetic customer_state so subsequent operations
/// (discount, edit_item) continue to use the correct GST type.
Future<Map<String, dynamic>> switchGstType({
  required String approvalId,
  required String newGstType, // 'IGST' or 'CGST_SGST'
}) async {
  try {
    final approvalRows = await supabase
        .from('draft_approvals')
        .select('approval_id, draft_invoice_id, shop_id, customer_id, customer_name, customer_state, proposed_items, proposed_tax_breakdown, proposed_total, approval_status, reviewed_by, reviewed_at, approval_notes, sale_id, created_at, updated_at, original_items, payment_status, amount_paid, due_amount, discount_type, discount_value, discount_amount, subtotal_before_discount, subtotal_after_discount')
        .eq('approval_id', approvalId)
        .eq('approval_status', 'PENDING')
        .single();

    final approvalData = Map<String, dynamic>.from(approvalRows as Map);
    final shopId = (approvalData['shop_id'] ?? '').toString();
    final proposedItems = (approvalData['proposed_items'] as List).map((itemJson) {
      final json = Map<String, dynamic>.from(itemJson as Map);
      final rawGstRate = (json['gstRate'] as num?)?.toDouble() ?? 0.0;
      return CartItem(
        productId: (json['productId'] ?? '').toString(),
        productName: json['productName']?.toString(),
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
        gstRate: rawGstRate > 0 ? rawGstRate : 18.0,
      );
    }).toList();

    // Read existing discount amount for invoice-level discounting
    final discountAmount = (approvalData['discount_amount'] as num?)?.toDouble() ?? 0.0;

    // Fetch shop config
    final shopRows = await supabase
        .from('shops')
        .select('id, state, gst_registration_number, gst_mode, business_type, created_at')
        .eq('id', shopId)
        .single();
    final shopData = Map<String, dynamic>.from(shopRows as Map);
    final shopState = (shopData['state'] ?? 'DL').toString();

    // Recalculate tax for IGST (inter-state) or CGST+SGST (intra-state)
    final isInterState = newGstType == 'IGST';
    // Build a synthetic customer state to trigger inter/intra-state calc.
    // For IGST, use a state guaranteed to differ from shopState.
    String customerState;
    if (isInterState) {
      // Pick a state that is definitely different from shopState
      customerState = shopState == 'DL' ? 'MH' : 'DL';
    } else {
      customerState = shopState;
    }

    final shopConfig = ShopConfig(
      shopId: shopId,
      state: shopState,
      gstRegistrationNumber: shopData['gst_registration_number']?.toString(),
      gstMode: GSTMode.registered,
      businessType: shopData['business_type']?.toString() ?? 'Retail',
      createdAt: DateTime.tryParse(shopData['created_at']?.toString() ?? '') ?? DateTime.now(),
    );

    final newTaxBreakdown = GSTCalculator.calculateTax(
      items: proposedItems,
      shopConfig: shopConfig,
      customerState: customerState,
      invoiceDiscount: discountAmount,
    );

    // Recalculate payment amounts with the new total
    final paymentStatus = _normalizePaymentStatus(
      approvalData['payment_status'],
      (approvalData['amount_paid'] as num?)?.toDouble() ?? 0.0,
      newTaxBreakdown.totalAmount,
    );

    final amountPaid = paymentStatus == 'PAID'
        ? newTaxBreakdown.totalAmount
        : paymentStatus == 'PARTIAL'
            ? (_roundToTwoDecimals((approvalData['amount_paid'] as num?)?.toDouble() ?? 0.0)).clamp(0.0, newTaxBreakdown.totalAmount)
            : 0.0;
    final dueAmount = _roundToTwoDecimals(newTaxBreakdown.totalAmount - amountPaid);

    // Persist customer_state so subsequent operations respect the GST type
    await supabase.from('draft_approvals').update({
      'proposed_tax_breakdown': {
        'subtotal': newTaxBreakdown.subtotal,
        'cgst_amount': newTaxBreakdown.cgstAmount,
        'sgst_amount': newTaxBreakdown.sgstAmount,
        'igst_amount': newTaxBreakdown.igstAmount,
        'gst_mode': newTaxBreakdown.gstMode,
        'applicable_state': newTaxBreakdown.applicableState,
        'tax_slab': newTaxBreakdown.taxSlab,
        'total_amount': newTaxBreakdown.totalAmount,
        'breakdown': newTaxBreakdown.breakdown,
        'rate_wise_summary': newTaxBreakdown.rateWiseSummary,
      },
      'proposed_total': newTaxBreakdown.totalAmount,
      'gst_type': newGstType,
      'customer_state': customerState, // persist so discount/edit ops stay consistent
      'payment_status': paymentStatus,
      'amount_paid': amountPaid,
      'due_amount': dueAmount,
    }).eq('approval_id', approvalId);

    return {
      'success': true,
      'newGstType': newGstType,
      'taxBreakdown': newTaxBreakdown,
    };
  } catch (e) {
    return {'success': false, 'error': 'Failed to switch GST type: $e'};
  }
}

/// Get approval details for display
Future<Map<String, dynamic>?> getApprovalDetails(String approvalId) async {
  try {
    final result = await supabase
        .from('draft_approvals')
        .select('approval_id, draft_invoice_id, shop_id, customer_id, customer_name, customer_state, proposed_items, proposed_tax_breakdown, proposed_total, approval_status, reviewed_by, reviewed_at, approval_notes, sale_id, created_at, updated_at, original_items, payment_status, amount_paid, due_amount, discount_type, discount_value, discount_amount, subtotal_before_discount, subtotal_after_discount')
        .eq('approval_id', approvalId)
        .single();
    return Map<String, dynamic>.from(result as Map);
  } catch (e) {
    return null;
  }
}

/// Approve a pending product deletion request and remove the products.
Future<Map<String, dynamic>> approveProductDeletion({
  required String requestId,
  required String reviewedBy,
}) async {
  try {
    final requestRows = await supabase
        .from('draft_product_deletions')
        .select('id, shop_id, products, status, created_at, updated_at, reviewed_by, reviewed_at, approval_notes, deleted_at')
        .eq('id', requestId)
        .eq('status', 'PENDING')
        .single();

    final requestData = Map<String, dynamic>.from(requestRows as Map);
    final products = (requestData['products'] as List<dynamic>)
        .map((product) => Map<String, dynamic>.from(product as Map))
        .toList();
    final productIds = products
        .map((product) => product['id']?.toString())
        .whereType<String>()
        .toList();

    if (productIds.isEmpty) {
      return {
        'success': false,
        'error': 'Deletion request does not contain any products.',
      };
    }

    await supabase.from('products').delete().inFilter('id', productIds);

    await supabase.from('draft_product_deletions').update({
      'status': 'APPROVED',
      'reviewed_by': reviewedBy,
      'reviewed_at': DateTime.now().toIso8601String(),
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', requestId);

    return {
      'success': true,
      'requestId': requestId,
      'itemCount': productIds.length,
      'message': '''✅ *Product Deletion Approved!*

    Removed ${productIds.length} product(s) from inventory.''',
      'products': products,
    };
  } catch (e) {
    return {
      'success': false,
      'error': 'Failed to approve product deletion: $e',
    };
  }
}

/// Reject a pending product deletion request.
Future<Map<String, dynamic>> rejectProductDeletion({
  required String requestId,
  required String reviewedBy,
  required String rejectionReason,
}) async {
  try {
    await supabase.from('draft_product_deletions').update({
      'status': 'REJECTED',
      'reviewed_by': reviewedBy,
      'reviewed_at': DateTime.now().toIso8601String(),
      'approval_notes': rejectionReason,
    }).eq('id', requestId);

    return {
      'success': true,
      'requestId': requestId,
      'message': '''❌ *Product Deletion Rejected*

    Reason: $rejectionReason

    _The product remains in inventory._''',
    };
  } catch (e) {
    return {
      'success': false,
      'error': 'Failed to reject product deletion: $e',
    };
  }
}

/// Get product deletion request details for display.
Future<Map<String, dynamic>?> getProductDeletionRequestDetails(String requestId) async {
  try {
    final result = await supabase
        .from('draft_product_deletions')
        .select('id, shop_id, products, status, created_at, updated_at, reviewed_by, reviewed_at, approval_notes, deleted_at')
        .eq('id', requestId)
        .single();
    return Map<String, dynamic>.from(result as Map);
  } catch (e) {
    return null;
  }
}

/// Approve a product batch and insert/update items in the products table atomically.
/// It detects whether a product is marked as a restock and performs an update (stock increment),
/// or a new product insertion.
Future<Map<String, dynamic>> approveProductBatch({
  required String batchId,
  required String reviewedBy,
}) async {
  try {
    final batchRows = await supabase
        .from('draft_product_batches')
        .select('id, shop_id, proposed_products, status, created_at, updated_at, reviewed_by, reviewed_at')
        .eq('id', batchId)
        .eq('status', 'PENDING')
        .single();

    final batchData = Map<String, dynamic>.from(batchRows as Map);
    final shopId = batchData['shop_id'] as String;
    final proposedProducts = batchData['proposed_products'] as List;

    final List<Map<String, dynamic>> productsToInsert = [];
    final List<Map<String, dynamic>> productsToUpdate = [];

    for (final p in proposedProducts) {
      final data = Map<String, dynamic>.from(p as Map);
      final isRestock = data['is_restock'] == true;
      final existingProductId = data['existing_product_id']?.toString();

      if (isRestock && existingProductId != null && existingProductId.isNotEmpty) {
        // Fetch current stock quantity to add atomically
        final currentProd = await supabase
            .from('products')
            .select('stock_quantity')
            .eq('id', existingProductId)
            .maybeSingle();

        final currentStock = currentProd != null
            ? (currentProd['stock_quantity'] as num?)?.toInt() ?? 0
            : 0;

        productsToUpdate.add({
          'id': existingProductId,
          'shop_id': shopId,
          'stock_quantity': currentStock + ((data['stock_quantity'] as num?)?.toInt() ?? 0),
          'price': (data['price'] as num?)?.toDouble() ?? 0.0,
          if (data['cost_price'] != null)
            'cost_price': (data['cost_price'] as num?)?.toDouble() ?? 0.0,
          if (data['category'] != null)
            'category': data['category'],
          if (data['unit'] != null)
            'unit': data['unit'],
        });
      } else {
        // New Product
        productsToInsert.add({
          'id': const Uuid().v4(),
          'shop_id': shopId,
          'name': data['name'],
          'price': (data['price'] as num?)?.toDouble() ?? 0.0,
          'stock_quantity': (data['stock_quantity'] as num?)?.toInt() ?? 0,
          'category': data['category'],
          'description': data['description'],
          'is_service': data['is_service'] ?? false,
          'gst_rate': (data['gst_rate'] as num?)?.toDouble() ?? 0.0,
          'hsn_sac_code': data['hsn_sac_code'],
          'metadata': data['metadata'] ?? {},
          if (data['cost_price'] != null)
            'cost_price': (data['cost_price'] as num?)?.toDouble() ?? 0.0,
          'unit': data['unit'] ?? 'pcs',
        });
      }
    }

    if (productsToInsert.isNotEmpty) {
      await supabase.from('products').insert(productsToInsert);
    }
    if (productsToUpdate.isNotEmpty) {
      await supabase.from('products').upsert(productsToUpdate);
    }

    await supabase
        .from('draft_product_batches')
        .update({
          'status': 'APPROVED',
          'reviewed_by': reviewedBy,
          'reviewed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', batchId);

    return {
      'success': true,
      'message': '✅ *Inventory Updated!*\n\n${proposedProducts.length} items added or restocked in your catalog.',
    };
  } catch (e) {
    print('Error in approveProductBatch: $e');
    return {'success': false, 'error': 'Failed to approve batch: $e'};
  }
}

/// Update a pending product batch draft's proposed products list
Future<Map<String, dynamic>> updateProductBatchDraft({
  required String batchId,
  required List<Map<String, dynamic>> products,
  double? invoiceTotal,
}) async {
  try {
    final batchRows = await supabase
        .from('draft_product_batches')
        .select('id, shop_id, status')
        .eq('id', batchId)
        .eq('status', 'PENDING')
        .single();

    final batchData = Map<String, dynamic>.from(batchRows as Map);
    final shopId = batchData['shop_id'] as String;

    // Recalculate restock flags/metadata on the updated products list
    final enrichedProducts = await enrichProposedProductsWithRestock(
      shopId: shopId,
      products: products,
    );

    final updateData = <String, dynamic>{
      'proposed_products': enrichedProducts,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (invoiceTotal != null) {
      updateData['invoice_total'] = invoiceTotal;
    }

    final updatedRow = await supabase
        .from('draft_product_batches')
        .update(updateData)
        .eq('id', batchId)
        .select('invoice_total')
        .single();

    return {
      'success': true,
      'products': enrichedProducts,
      'invoice_total': (updatedRow as Map)['invoice_total'],
    };
  } catch (e) {
    print('Error in updateProductBatchDraft: $e');
    return {'success': false, 'error': 'Failed to update batch: $e'};
  }
}

/// Reject a product batch
Future<Map<String, dynamic>> rejectProductBatch({
  required String batchId,
  required String reviewedBy,
}) async {
  try {
    await supabase
        .from('draft_product_batches')
        .update({
          'status': 'REJECTED',
          'reviewed_by': reviewedBy,
          'reviewed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', batchId);

    return {
      'success': true,
      'message': '❌ *Batch Rejected*\n\nItems were not added to inventory.',
    };
  } catch (e) {
    return {'success': false, 'error': 'Failed to reject batch: $e'};
  }
}

/// Get product batch details
Future<Map<String, dynamic>?> getProductBatchDetails(String batchId) async {
  try {
    final result = await supabase
        .from('draft_product_batches')
        .select('id, shop_id, proposed_products, status, created_at, updated_at, reviewed_by, reviewed_at')
        .eq('id', batchId)
        .single();
    return Map<String, dynamic>.from(result as Map);
  } catch (e) {
    return null;
  }
}
