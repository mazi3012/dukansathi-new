import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../presentation/chat/models/ai_intent.dart';
import '../models/cart_item.dart';
import '../models/draft_approval.dart';
import '../models/tax_breakdown.dart';
import '../models/shop_config.dart';
import '../models/product.dart';
import '../models/customer.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/customer_repository.dart';
import '../services/gst_calculator.dart';
import '../core/session.dart';

class IntentExecutor {
  static final IntentExecutor _instance = IntentExecutor._();
  factory IntentExecutor() => _instance;
  IntentExecutor._();

  final _uuid = const Uuid();

  /// Executes an AiIntent locally on SQFlite and returns a draft approval or confirmation card payload.
  Future<Map<String, dynamic>> execute(AiIntent intent) async {
    final session = UserSession();
    final shopId = session.shopId;
    if (shopId == null) {
      return {
        'success': false,
        'error': 'No active shop session found. Please set up your shop first.',
      };
    }

    try {
      switch (intent.type) {
        case AiIntentType.addProduct:
          return await _handleAddProduct(intent, shopId);
        case AiIntentType.createInvoice:
          return await _handleCreateInvoice(intent, shopId, session.shopConfig);
        default:
          return {
            'success': false,
            'error': 'Unknown intent type.',
          };
      }
    } catch (e, stack) {
      debugPrint('[IntentExecutor] Execution failed: $e\n$stack');
      return {
        'success': false,
        'error': 'Execution error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> _handleAddProduct(AiIntent intent, String shopId) async {
    final productsPayload = intent.payload['products'] as List<dynamic>? ?? [];
    if (productsPayload.isEmpty) {
      return {
        'success': false,
        'error': 'No products provided in intent payload.',
      };
    }

    final productRepo = ProductRepository();
    final List<Product> addedProducts = [];

    for (final item in productsPayload) {
      final json = Map<String, dynamic>.from(item as Map);
      final String name = json['name']?.toString() ?? 'Unnamed Product';
      final double price = (json['price'] as num?)?.toDouble() ?? 0.0;
      final int stock = (json['stock_quantity'] as num?)?.toInt() ?? (json['stock'] as num?)?.toInt() ?? 0;
      final double gstRate = (json['gst_rate'] as num?)?.toDouble() ?? 18.0;
      final String? hsn = json['hsn_sac_code']?.toString();
      final String category = json['category']?.toString() ?? 'General';
      final String? desc = json['description']?.toString();

      final product = Product(
        id: _uuid.v4(),
        shopId: shopId,
        name: name,
        price: price,
        stockQuantity: stock,
        category: category,
        description: desc,
        isService: false,
        gstRate: gstRate,
        hsnSacCode: hsn,
        costPrice: (json['cost_price'] as num?)?.toDouble() ?? (price * 0.7),
        unit: json['unit']?.toString() ?? 'pcs',
      );

      // Do NOT save to DB here. This is a draft, wait for UI approval!
      addedProducts.add(product);
    }

    return {
      'success': true,
      'type': 'ADD_PRODUCT_CONFIRMATION',
      'batchId': _uuid.v4(),
      'status': 'PENDING',
      'products': addedProducts.map((p) => p.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> _handleCreateInvoice(
    AiIntent intent,
    String shopId,
    ShopConfig shopConfig,
  ) async {
    final customerName = intent.payload['customerName']?.toString();
    final requestedItems = intent.payload['requestedItems'] as Map<String, dynamic>? ?? {};

    if (requestedItems.isEmpty) {
      return {
        'success': false,
        'error': 'No items requested for billing.',
      };
    }

    // 1. Fetch local products for fuzzy matching
    final allProducts = await ProductRepository().getProducts(shopId);

    // 2. Resolve requested items to local products
    final List<CartItem> cartItems = [];
    for (final entry in requestedItems.entries) {
      final reqName = entry.key;
      final int qty = (entry.value as num).toInt();

      final matched = _findMatchingProduct(reqName, allProducts);

      if (matched != null) {
        cartItems.add(CartItem(
          productId: matched.id,
          productName: matched.name,
          quantity: qty,
          unitPrice: matched.price,
          gstRate: matched.gstRate,
        ));
      } else {
        // Fallback: Create a synthetic product to ensure billing doesn't crash
        final tempId = 'temp-${_uuid.v4().substring(0, 8)}';
        cartItems.add(CartItem(
          productId: tempId,
          productName: reqName,
          quantity: qty,
          unitPrice: 100.0, // fallback price
          gstRate: 18.0, // fallback rate
        ));
      }
    }

    // 3. Resolve customer state (default to shop's own state)
    String customerState = shopConfig.state;
    String? customerId;

    if (customerName != null && customerName.isNotEmpty) {
      final allCustomers = await CustomerRepository().getCustomers(shopId);
      final matchedCust = _findMatchingCustomer(customerName, allCustomers);
      if (matchedCust != null) {
        customerId = matchedCust.id;
        // If customer doesn't have metadata/state, default to shop's own state
        customerState = shopConfig.state;
      }
    }

    // 4. Calculate tax locally
    final taxBreakdown = GSTCalculator.calculateTax(
      items: cartItems,
      shopConfig: shopConfig,
      customerState: customerState,
      invoiceDiscount: 0.0,
    );

    // 5. Construct a synthetic DraftApproval object
    final approval = DraftApproval(
      approvalId: _uuid.v4(),
      shopId: shopId,
      customerId: customerId,
      customerName: customerName ?? 'Walk-in Customer',
      customerState: customerState,
      createdAt: DateTime.now(),
      proposedItems: cartItems,
      proposedTaxBreakdown: taxBreakdown,
      proposedTotal: taxBreakdown.totalAmount,
      approvalStatus: ApprovalStatus.pending,
      paymentStatus: 'UNPAID',
      amountPaid: 0.0,
      dueAmount: taxBreakdown.totalAmount,
    );

    return {
      'success': true,
      'type': 'INVOICE_DRAFT',
      'draft': approval.toJson(),
    };
  }

  Product? _findMatchingProduct(String requestedName, List<Product> products) {
    final reqNorm = requestedName.toLowerCase().trim();
    if (reqNorm.isEmpty) return null;

    // 1. Exact match
    for (final p in products) {
      if (p.name.toLowerCase().trim() == reqNorm) {
        return p;
      }
    }

    // 2. Substring match
    Product? bestSubMatch;
    for (final p in products) {
      final pNorm = p.name.toLowerCase().trim();
      if (pNorm.contains(reqNorm) || reqNorm.contains(pNorm)) {
        bestSubMatch = p;
        break;
      }
    }
    if (bestSubMatch != null) return bestSubMatch;

    // 3. Token overlap match
    final reqTokens = reqNorm.split(RegExp(r'\s+'));
    Product? bestTokenMatch;
    int maxOverlap = 0;
    for (final p in products) {
      final pNorm = p.name.toLowerCase().trim();
      final pTokens = pNorm.split(RegExp(r'\s+'));
      int overlap = 0;
      for (final t in reqTokens) {
        if (pTokens.contains(t)) overlap++;
      }
      if (overlap > maxOverlap) {
        maxOverlap = overlap;
        bestTokenMatch = p;
      }
    }

    return bestTokenMatch;
  }

  Customer? _findMatchingCustomer(String requestedName, List<Customer> customers) {
    final reqNorm = requestedName.toLowerCase().trim();
    if (reqNorm.isEmpty) return null;

    for (final c in customers) {
      if (c.name.toLowerCase().trim() == reqNorm) {
        return c;
      }
    }

    for (final c in customers) {
      final cNorm = c.name.toLowerCase().trim();
      if (cNorm.contains(reqNorm) || reqNorm.contains(cNorm)) {
        return c;
      }
    }

    return null;
  }
}
