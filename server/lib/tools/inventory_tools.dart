import 'package:schemantic/schemantic.dart';
import 'package:uuid/uuid.dart';

import '../core/database.dart';
import '../runtime/genkit_runtime.dart';
import '../shared/models/product.dart';

Product _productFromRow(Map row) {
  final data = Map<String, dynamic>.from(row);
  return Product.fromJson({
    'id': data['id']?.toString() ?? '',
    'shop_id': data['shop_id']?.toString() ?? '',
    'name': data['name']?.toString() ?? '',
    'price': (data['price'] as num?)?.toDouble() ?? 0.0,
    'stock_quantity': (data['stock_quantity'] as num?)?.toInt() ?? 0,
    'category': data['category']?.toString() ?? '',
    'description': data['description']?.toString(),
    'is_service': data['is_service'] as bool? ?? false,
    'gst_rate': (data['gst_rate'] as num?)?.toDouble() ?? 0.0,
    'hsn_sac_code': data['hsn_sac_code']?.toString(),
    'cost_price': (data['cost_price'] as num?)?.toDouble() ?? 0.0,
    'metadata': data['metadata'] as Map<String, dynamic>? ?? {},
  });
}

Future<List<Product>> findInventoryProducts(String rawQuery, [String? shopId]) async {
  final query = rawQuery.trim();
  if (query.isEmpty) {
    return <Product>[];
  }

  var select = supabase
      .from('products')
      .select('id, shop_id, name, price, stock_quantity, category, cost_price')
      .ilike('name', '%$query%');

  if (shopId != null) {
    select = select.eq('shop_id', shopId);
  }

  final response = await select;

  if ((response as List).isNotEmpty) {
    return response
        .map((row) => _productFromRow(row as Map))
        .toList();
  }

  // Fall back to token match for minor spelling differences (e.g., ashirvad vs aashirvaad).
  final tokens = query
      .split(RegExp(r'\s+'))
      .map((t) => t.trim())
      .where((t) => t.length >= 3)
      .toList();

  if (tokens.isEmpty) {
    return <Product>[];
  }

  final byId = <String, Product>{};
  for (final token in tokens) {
    var tokenSelect = supabase
        .from('products')
        .select('id, shop_id, name, price, stock_quantity, category, cost_price')
        .ilike('name', '%$token%');

    if (shopId != null) {
      tokenSelect = tokenSelect.eq('shop_id', shopId);
    }

    final tokenResponse = await tokenSelect;

    for (final row in (tokenResponse as List<dynamic>)) {
      final product = _productFromRow(row as Map);
      byId[product.id] = product;
    }
  }

  return byId.values.toList();
}

final SchemanticType<Map<String, dynamic>> checkInventoryInputSchema =
    SchemanticType.from<Map<String, dynamic>>(
  jsonSchema: {
    'type': 'object',
    'properties': {
      'productName': {'type': 'string'},
    },
    'required': ['productName'],
  },
  parse: (json) => Map<String, dynamic>.from(json as Map),
);

final checkInventoryTool = ai.defineTool<Map<String, dynamic>, List<Product>>(
  name: 'checkInventory',
  description: 'Find inventory items that match a product name fragment.',
  inputSchema: checkInventoryInputSchema,
  fn: (input, context) async {
    final query = (input['productName'] as String?) ?? '';
    final rawShopId = input['shopId'] as String?;
    final shopId = (isValidUuid(rawShopId) ? rawShopId : null) ?? 
                   (context.context?['shopId'] as String?) ?? 
                   await getShopIdForUser(context.context?['userIdentifier'] as String?);
    return findInventoryProducts(query, shopId);
  },
);

final checkInventory = checkInventoryTool;

final SchemanticType<Map<String, dynamic>> browseCatalogInputSchema =
    SchemanticType.from<Map<String, dynamic>>(
  jsonSchema: {
    'type': 'object',
    'properties': {
      'category': {'type': 'string'},
    },
  },
  parse: (json) => Map<String, dynamic>.from(json as Map),
);

final browseCatalogTool =
    ai.defineTool<Map<String, dynamic>, Map<String, dynamic>>(
  name: 'browseCatalogTool',
  description:
      "Use this ONLY when the user asks for a list of available products, 'what do you sell?', or wants to see items in a category.",
  inputSchema: browseCatalogInputSchema,
  fn: (input, context) async {
    final category = (input['category'] as String?)?.trim();
    final rawShopId = input['shopId'] as String?;
    final shopId = (isValidUuid(rawShopId) ? rawShopId : null) ?? 
                   (context.context?['shopId'] as String?) ?? 
                   await getShopIdForUser(context.context?['userIdentifier'] as String?);
    
    var query = supabase
        .from('products')
        .select('id, shop_id, name, price, stock_quantity, category, cost_price')
        .eq('shop_id', shopId);

    final rows = (category != null && category.isNotEmpty)
        ? await query.eq('category', category).limit(20)
        : await query.limit(20);

    final products = (rows as List<dynamic>)
        .map((row) => _productFromRow(row as Map))
        .toList();

    if (products.isEmpty) {
      return {
        'message': 'Your catalog is empty. No products are registered in this shop yet.',
        'items': <Map<String, dynamic>>[],
      };
    }

    return {
      'message': 'Catalog items',
      'items': products.map((p) => p.toJson()).toList(),
    };
  },
);

final browseCatalog = browseCatalogTool;

final SchemanticType<Map<String, dynamic>> proposeProductsInputSchema =
    SchemanticType.from<Map<String, dynamic>>(
  jsonSchema: {
    'type': 'object',
    'properties': {
      'invoice_total': {'type': 'number'},
      'products': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'price': {'type': 'number'},
            'stock_quantity': {'type': 'integer'},
            'category': {'type': 'string'},
            'description': {'type': 'string'},
            'is_service': {'type': 'boolean'},
            'gst_rate': {'type': 'number'},
            'hsn_sac_code': {'type': 'string'},
            'cost_price': {'type': 'number'},
            'unit': {'type': 'string'},
            'confidence': {'type': 'number'},
            'uncertain_fields': {
              'type': 'array',
              'items': {'type': 'string'}
            },
          },
          'required': ['name', 'price', 'category'],
        },
      },
    },
    'required': ['products'],
  },
  parse: (json) => Map<String, dynamic>.from(json as Map),
);

Future<List<Map<String, dynamic>>> enrichProposedProductsWithRestock({
  required String shopId,
  required List<Map<String, dynamic>> products,
}) async {
  try {
    final existingProductRows = await supabase
        .from('products')
        .select('id, name, price, cost_price, stock_quantity, category')
        .eq('shop_id', shopId);

    final existingProducts = (existingProductRows as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    final List<Map<String, dynamic>> enriched = [];

    for (final p in products) {
      final name = (p['name'] as String?)?.trim() ?? '';
      
      final match = existingProducts.firstWhere(
        (ep) => (ep['name'] as String).trim().toLowerCase() == name.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );

      if (match.isNotEmpty) {
        enriched.add({
          ...p,
          'is_restock': true,
          'existing_product_id': match['id'],
          'existing_stock': match['stock_quantity'] ?? 0,
          'existing_price': (match['price'] as num?)?.toDouble() ?? 0.0,
        });
      } else {
        enriched.add({
          ...p,
          'is_restock': false,
        });
      }
    }

    return enriched;
  } catch (e) {
    print('Error enriching proposed products: $e');
    return products;
  }
}

final proposeProductsTool =
    ai.defineTool<Map<String, dynamic>, Map<String, dynamic>>(
  name: 'proposeProducts',
  description:
      'Propose one or more products or services to be added to the inventory. This creates a draft that REQUIRES human approval.',
  inputSchema: proposeProductsInputSchema,
  fn: (input, context) async {
    final products = (input['products'] as List<dynamic>)
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();

    final rawShopId = input['shopId'] as String?;
    final shopId = (isValidUuid(rawShopId) ? rawShopId : null) ?? 
                   (context.context?['shopId'] as String?) ?? 
                   await getShopIdForUser(context.context?['userIdentifier'] as String?);
    final invoiceTotal = input['invoice_total'] as num?;

    try {
      final enriched = await enrichProposedProductsWithRestock(
        shopId: shopId,
        products: products,
      );

      final response = await supabase.from('draft_product_batches').insert({
        'shop_id': shopId,
        'proposed_products': enriched,
        'status': 'PENDING',
        if (invoiceTotal != null) 'invoice_total': invoiceTotal.toDouble(),
      }).select('id').single();

      return {
        'message':
            'Product draft created. Human approval is required to finalize.',
        'batchId': response['id'],
        'itemCount': enriched.length,
        'products': enriched,
        if (invoiceTotal != null) 'invoice_total': invoiceTotal.toDouble(),
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': 'Failed to create product draft: $e',
      };
    }
  },
);

final proposeProducts = proposeProductsTool;

Future<Map<String, dynamic>> createProductBatchRequest({
  required String userIdentifier,
  required List<Map<String, dynamic>> products,
  String? shopId,
  double? invoiceTotal,
}) async {
  if (products.isEmpty) {
    return {
      'success': false,
      'message': 'No products were provided.',
    };
  }

  try {
    final effectiveShopId = shopId ?? await getShopIdForUser(userIdentifier);
    final enriched = await enrichProposedProductsWithRestock(
      shopId: effectiveShopId,
      products: products,
    );

    final response = await supabase.from('draft_product_batches').insert({
      'shop_id': effectiveShopId,
      'proposed_products': enriched,
      'status': 'PENDING',
      if (invoiceTotal != null) 'invoice_total': invoiceTotal,
    }).select('id').single();

    return {
      'success': true,
      'batchId': response['id'],
      'itemCount': enriched.length,
      'products': enriched,
      if (invoiceTotal != null) 'invoice_total': invoiceTotal,
    };
  } catch (e) {
    return {
      'success': false,
      'message': 'Failed to create product batch: $e',
    };
  }
}

Future<Map<String, dynamic>> createProductDeletionRequest({
  required String userIdentifier,
  required String rawQuery,
  String? reason,
  String? shopId,
}) async {
  final normalizedQuery = rawQuery.toLowerCase().trim();
  final effectiveShopId = shopId ?? await getShopIdForUser(userIdentifier);

  final listQuery = normalizedQuery.contains('last item') ||
          normalizedQuery.contains('last one') ||
          normalizedQuery.contains('first item') ||
          normalizedQuery.contains('first one') ||
          normalizedQuery.contains('1st one')
      ? await supabase
          .from('products')
          .select('id, shop_id, name, price, stock_quantity, category, cost_price')
          .eq('shop_id', effectiveShopId)
          .limit(50)
      : null;

  final matches = listQuery == null
      ? await findInventoryProducts(rawQuery, effectiveShopId)
      : (listQuery as List<dynamic>).map((row) => _productFromRow(row as Map)).toList();

  if (matches.isEmpty) {
    return {
      'success': false,
      'message': 'No products matched "$rawQuery".',
    };
  }

  final selectedProducts = normalizedQuery.contains('last item') ||
          normalizedQuery.contains('last one')
      ? [matches.last]
      : normalizedQuery.contains('first item') ||
              normalizedQuery.contains('first one') ||
              normalizedQuery.contains('1st one')
          ? [matches.first]
          : matches.length > 1 && matches.first.name.toLowerCase() != rawQuery.toLowerCase()
              ? [matches.first]
              : matches;

  final requestId = const Uuid().v4();
  final payload = selectedProducts.map((product) {
    return {
      'id': product.id,
      'name': product.name,
      'price': product.price,
      'stock_quantity': product.stockQuantity,
      'category': product.category,
      'cost_price': product.costPrice,
    };
  }).toList();

  await supabase.from('draft_product_deletions').insert({
    'id': requestId,
    'shop_id': effectiveShopId,
    'requested_by': userIdentifier,
    'products': payload,
    'reason': reason,
    'status': 'PENDING',
  });

  return {
    'success': true,
    'requestId': requestId,
    'productName': payload.first['name']?.toString() ?? rawQuery,
    'itemCount': payload.length,
    'products': payload,
  };
}

final SchemanticType<Map<String, dynamic>> requestProductDeletionInputSchema =
    SchemanticType.from<Map<String, dynamic>>(
  jsonSchema: {
    'type': 'object',
    'properties': {
      'productName': {'type': 'string'},
      'product_name': {'type': 'string'},
      'reason': {'type': 'string'},
    },
    'required': ['productName'],
  },
  parse: (json) => Map<String, dynamic>.from(json as Map),
);

final requestProductDeletionTool =
    ai.defineTool<Map<String, dynamic>, Map<String, dynamic>>(
  name: 'requestProductDeletion',
  description:
      'Create a human-approval request before deleting one or more products from inventory.',
  inputSchema: requestProductDeletionInputSchema,
  fn: (input, context) async {
    final rawName = ((input['productName'] as String?) ?? (input['product_name'] as String?))?.trim() ?? '';
    final reason = (input['reason'] as String?)?.trim();
    if (rawName.isEmpty) {
      return {
        'success': false,
        'message': 'Product name is required.',
      };
    }

    final result = await createProductDeletionRequest(
      userIdentifier: context.context?['userIdentifier']?.toString() ?? '',
      rawQuery: rawName,
      reason: reason,
      shopId: context.context?['shopId'] as String?,
    );

    if (result['success'] != true) {
      return result;
    }

    return {
      'success': true,
      'message': '''🗑 *Product Deletion Request Created*

Delete Request ID: ${result['requestId']}
Items: ${result['itemCount']}

Human approval is required before any product is removed.''',
      'requestId': result['requestId'],
      'itemCount': result['itemCount'],
      'products': result['products'],
    };
  },
);

final requestProductDeletion = requestProductDeletionTool;
