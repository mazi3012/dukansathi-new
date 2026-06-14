import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_box.dart';
import '../../../core/session.dart';
import '../../../models/product.dart';
import '../../../data/repositories/product_repository.dart';
import '../../../core/config.dart';

class InventoryDraftCard extends StatefulWidget {
  final dynamic payload;
  final VoidCallback? onApproved;
  const InventoryDraftCard({super.key, this.payload, this.onApproved});

  @override
  State<InventoryDraftCard> createState() => _InventoryDraftCardState();
}

class _InventoryDraftCardState extends State<InventoryDraftCard> {
  bool _isApproving = false;
  bool _isSavingDraft = false;
  bool _isApproved = false;
  bool _isEditing = false;
  String? _batchId;
  late List<dynamic> _products;
  List<Map<String, dynamic>> _editableProducts = [];
  double? _invoiceTotal;
  final TextEditingController _invoiceTotalController = TextEditingController();

  // Editing Controllers
  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _priceControllers = [];
  final List<TextEditingController> _costPriceControllers = [];
  final List<TextEditingController> _qtyControllers = [];
  final List<TextEditingController> _categoryControllers = [];
  final List<TextEditingController> _profitPercentControllers = [];
  final List<String> _selectedUnits = [];

  @override
  void initState() {
    super.initState();
    _parsePayload();
    if (!_isApproved) {
      _isEditing = true;
      _initControllers();
    }
  }

  @override
  void didUpdateWidget(InventoryDraftCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.payload != oldWidget.payload) {
      setState(() {
        _parsePayload();
        if (!_isApproved) {
          _isEditing = true;
          _initControllers();
        }
      });
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    _invoiceTotalController.dispose();
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in _nameControllers) c.dispose();
    _nameControllers.clear();
    for (final c in _priceControllers) c.dispose();
    _priceControllers.clear();
    for (final c in _costPriceControllers) c.dispose();
    _costPriceControllers.clear();
    for (final c in _qtyControllers) c.dispose();
    _qtyControllers.clear();
    for (final c in _categoryControllers) c.dispose();
    _categoryControllers.clear();
    for (final c in _profitPercentControllers) c.dispose();
    _profitPercentControllers.clear();
    _selectedUnits.clear();
  }

  void _initControllers() {
    _disposeControllers();
    
    _invoiceTotalController.text = _invoiceTotal != null ? _invoiceTotal!.toStringAsFixed(2) : '';

    final allowedUnits = const ['pcs', 'box', 'dozen', 'packet', 'kg', 'g', 'ltr', 'ml'];
    for (final p in _editableProducts) {
      final name = p['name'] ?? p['item_name'] ?? '';
      final price = (p['price'] ?? p['price_per_unit'] ?? 0.0).toDouble();
      final costPrice = (p['cost_price'] ?? p['cp'] ?? 0.0).toDouble();
      final stock = p['stock_quantity'] ?? p['quantity'] ?? 0;
      final category = p['category'] ?? 'General';
      
      String unit = p['unit']?.toString() ?? 'pcs';
      if (!allowedUnits.contains(unit)) {
        unit = 'pcs';
      }

      _nameControllers.add(TextEditingController(text: name.toString()));
      _priceControllers.add(TextEditingController(text: price.toString()));
      _costPriceControllers.add(TextEditingController(text: costPrice.toString()));
      _qtyControllers.add(TextEditingController(text: stock.toString()));
      _categoryControllers.add(TextEditingController(text: category.toString()));

      double profitPercent = 0.0;
      if (costPrice > 0) {
        profitPercent = ((price - costPrice) / costPrice) * 100.0;
      }
      _profitPercentControllers.add(TextEditingController(
        text: costPrice > 0 ? profitPercent.toStringAsFixed(1) : '0.0',
      ));
      _selectedUnits.add(unit);
    }
  }

  void _parsePayload() {
    final payload = widget.payload;
    debugPrint('[InventoryDraftCard] Parsing payload type: ${payload.runtimeType}');
    if (payload is List) {
      _products = payload;
      _batchId = null;
      _invoiceTotal = null;
      _invoiceTotalController.clear();
      debugPrint('[InventoryDraftCard] Parsed as List with ${_products.length} products');
    } else if (payload is Map) {
      _products = payload['items'] ?? payload['inventory'] ?? payload['products'] ?? [];
      _batchId = payload['batchId']?.toString() ?? payload['id']?.toString();
      _isApproved = payload['status'] == 'APPROVED';
      final double? parsedTotal = (payload['invoice_total'] ?? payload['invoiceTotal']) != null
          ? (payload['invoice_total'] ?? payload['invoiceTotal']).toDouble()
          : null;
      _invoiceTotal = parsedTotal;
      _invoiceTotalController.text = parsedTotal != null ? parsedTotal.toStringAsFixed(2) : '';
      debugPrint('[InventoryDraftCard] Parsed as Map - products: ${_products.length}, batchId: $_batchId, status: ${payload['status']}');
    } else {
      _products = [];
      _invoiceTotal = null;
      _invoiceTotalController.clear();
      debugPrint('[InventoryDraftCard] Unknown payload type, defaulting to empty products');
    }

    _editableProducts = _products.map((p) => Map<String, dynamic>.from(p as Map)).toList();
  }

  double _calculateTotalCost() {
    double total = 0.0;
    if (_isEditing) {
      for (int i = 0; i < _editableProducts.length; i++) {
        final cp = double.tryParse(_costPriceControllers[i].text) ?? 0.0;
        final qty = int.tryParse(_qtyControllers[i].text) ?? 0;
        total += cp * qty;
      }
    } else {
      for (final p in _products) {
        final cp = (p['cost_price'] ?? p['cp'] ?? 0.0).toDouble();
        final qty = (p['stock_quantity'] ?? p['quantity'] ?? 0).toInt();
        total += cp * qty;
      }
    }
    return total;
  }



  Future<void> _saveDraft() async {
    // Collect updated data from controllers
    for (int i = 0; i < _editableProducts.length; i++) {
      final p = _editableProducts[i];
      p['name'] = _nameControllers[i].text.trim();
      p['price'] = double.tryParse(_priceControllers[i].text) ?? 0.0;
      p['cost_price'] = double.tryParse(_costPriceControllers[i].text) ?? 0.0;
      p['stock_quantity'] = int.tryParse(_qtyControllers[i].text) ?? 0;
      p['category'] = _categoryControllers[i].text.trim();
      p['unit'] = _selectedUnits[i];
    }

    final double? updatedInvoiceTotal = double.tryParse(_invoiceTotalController.text);

    if (_batchId == null) {
      // Local-only draft updates
      setState(() {
        _products = List<Map<String, dynamic>>.from(_editableProducts);
        _invoiceTotal = updatedInvoiceTotal;
        _parsePayload();
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Draft updated locally."),
          backgroundColor: AppColors.success,
        ),
      );
      return;
    }

    setState(() => _isSavingDraft = true);
    final client = http.Client();
    try {
      final response = await client.post(
        AppConfig.getApiUri('/api/update-batch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'batchId': _batchId,
          'products': _editableProducts,
          'invoice_total': updatedInvoiceTotal,
        }),
      );

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['success'] == true) {
          setState(() {
            _products = resData['products'] ?? _editableProducts;
            _invoiceTotal = resData['invoice_total'] != null 
                ? (resData['invoice_total'] as num).toDouble() 
                : updatedInvoiceTotal;
            _parsePayload();
            _isEditing = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Draft changes saved!"),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          throw Exception(resData['error'] ?? 'Failed to update draft');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[InventoryDraftCard] Error saving draft: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to save draft: $e"),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      client.close();
      setState(() => _isSavingDraft = false);
    }
  }

  Future<void> _approveBatch() async {
    if (_isApproved) return;

    final calculatedTotal = _calculateTotalCost();
    final invoiceVal = _invoiceTotal ?? 0.0;
    final double diff = (invoiceVal - calculatedTotal).abs();
    final bool isReconciled = _invoiceTotal != null && diff < 0.1;

    if (_invoiceTotal != null && !isReconciled) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : AppColors.lightBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Iconsax.warning_2, color: AppColors.error, size: 28),
              SizedBox(width: 12),
              Text("Valuation Mismatch", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            "The calculated total cost (₹${calculatedTotal.toStringAsFixed(2)}) does not match the invoice total (₹${_invoiceTotal!.toStringAsFixed(2)}).\n\nAre you sure you want to approve and import this batch anyway?",
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text("Approve Anyway", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _isApproving = true);
    final client = http.Client();
    try {
      if (_isEditing) {
        for (int i = 0; i < _editableProducts.length; i++) {
          final p = _editableProducts[i];
          p['name'] = _nameControllers[i].text.trim();
          p['price'] = double.tryParse(_priceControllers[i].text) ?? 0.0;
          p['cost_price'] = double.tryParse(_costPriceControllers[i].text) ?? 0.0;
          p['stock_quantity'] = int.tryParse(_qtyControllers[i].text) ?? 0;
          p['category'] = _categoryControllers[i].text.trim();
          p['unit'] = _selectedUnits[i];
        }

        final double? updatedInvoiceTotal = double.tryParse(_invoiceTotalController.text);

        if (_batchId != null) {
          final updateResponse = await client.post(
            AppConfig.getApiUri('/api/update-batch'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'batchId': _batchId,
              'products': _editableProducts,
              'invoice_total': updatedInvoiceTotal,
            }),
          );
          if (updateResponse.statusCode == 200) {
            final resData = jsonDecode(updateResponse.body);
            if (resData['success'] == true) {
              _products = resData['products'] ?? _editableProducts;
              _invoiceTotal = resData['invoice_total'] != null 
                  ? (resData['invoice_total'] as num).toDouble() 
                  : updatedInvoiceTotal;
            }
          }
        } else {
          _products = List<Map<String, dynamic>>.from(_editableProducts);
          _invoiceTotal = updatedInvoiceTotal;
        }
      }

      // 1. If batch ID exists on server, invoke approve-batch endpoint to ensure server consistency
      if (_batchId != null) {
        final response = await client.post(
          AppConfig.getApiUri('/api/approve-batch'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'batchId': _batchId,
            'userId': UserSession().userId ?? 'web-user',
          }),
        );
        if (response.statusCode != 200) {
          final errBody = jsonDecode(response.body);
          throw Exception(errBody['error'] ?? 'Failed to approve draft on server');
        }
      }

      // 2. Save/Update products locally in SQLite repository (only if not a server batch)
      if (_batchId == null) {
        final productRepo = ProductRepository();
        final currentShopId = UserSession().shopId ?? 'default_shop';

        for (final pMap in _products) {
          final cleanMap = <String, dynamic>{};
          final pData = Map<String, dynamic>.from(pMap as Map);

          final isRestock = pData['is_restock'] == true;
          final existingId = pData['existing_product_id']?.toString();

          if (isRestock && existingId != null && existingId.isNotEmpty) {
            // It's a restock! We fetch existing product and add the quantity
            final existingProduct = await productRepo.getProductById(existingId);
            if (existingProduct != null) {
              final newQty = existingProduct.stockQuantity + ((pData['stock_quantity'] ?? pData['quantity'] ?? 0) as num).toInt();
              final updatedProduct = Product(
                id: existingProduct.id,
                shopId: existingProduct.shopId,
                name: pData['name']?.toString() ?? existingProduct.name,
                price: (pData['price'] as num?)?.toDouble() ?? existingProduct.price,
                stockQuantity: newQty,
                category: pData['category']?.toString() ?? existingProduct.category,
                description: pData['description']?.toString() ?? existingProduct.description,
                isService: existingProduct.isService,
                gstRate: (pData['gst_rate'] as num?)?.toDouble() ?? existingProduct.gstRate,
                hsnSacCode: pData['hsn_sac_code']?.toString() ?? existingProduct.hsnSacCode,
                barcode: pData['barcode']?.toString() ?? existingProduct.barcode,
                costPrice: (pData['cost_price'] as num?)?.toDouble() ?? existingProduct.costPrice,
                metadata: existingProduct.metadata,
                unit: pData['unit']?.toString() ?? existingProduct.unit,
              );
              await productRepo.saveProduct(updatedProduct);
              continue;
            }
          }

          // New product insertion
          cleanMap['id'] = pData['id']?.toString() ?? const Uuid().v4();
          cleanMap['shop_id'] = pData['shop_id']?.toString() ?? pData['shopId']?.toString() ?? currentShopId;
          cleanMap['name'] = pData['name']?.toString() ?? pData['item_name']?.toString() ?? 'Unnamed Product';
          
          final rawPrice = pData['price'] ?? pData['price_per_unit'] ?? 0.0;
          cleanMap['price'] = rawPrice is num ? rawPrice.toDouble() : double.tryParse(rawPrice.toString()) ?? 0.0;
          
          final rawStock = pData['stock_quantity'] ?? pData['quantity'] ?? 0;
          cleanMap['stock_quantity'] = rawStock is num ? rawStock.toInt() : int.tryParse(rawStock.toString()) ?? 0;
          
          cleanMap['category'] = pData['category']?.toString() ?? 'General';
          cleanMap['description'] = pData['description']?.toString();
          
          final rawIsService = pData['is_service'] ?? pData['isService'] ?? false;
          cleanMap['is_service'] = rawIsService is bool ? rawIsService : (rawIsService.toString().toLowerCase() == 'true' || rawIsService == 1);
          
          final rawGstRate = pData['gst_rate'] ?? pData['gst'] ?? 0.0;
          cleanMap['gst_rate'] = rawGstRate is num ? rawGstRate.toDouble() : double.tryParse(rawGstRate.toString()) ?? 0.0;
          
          cleanMap['hsn_sac_code'] = pData['hsn_sac_code']?.toString() ?? pData['hsn_code']?.toString() ?? pData['hsnSacCode']?.toString();
          cleanMap['barcode'] = pData['barcode']?.toString();
          
          final rawCostPrice = pData['cost_price'] ?? pData['cp'] ?? 0.0;
          cleanMap['cost_price'] = rawCostPrice is num ? rawCostPrice.toDouble() : double.tryParse(rawCostPrice.toString()) ?? 0.0;
          
          cleanMap['unit'] = pData['unit']?.toString() ?? 'pcs';
          
          if (pData['metadata'] is Map) {
            cleanMap['metadata'] = Map<String, dynamic>.from(pData['metadata']);
          } else {
            cleanMap['metadata'] = <String, dynamic>{};
          }

          final product = Product.fromJson(cleanMap);
          await productRepo.saveProduct(product);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Draft Approved & Added to Inventory!"),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() {
          _isApproved = true;
        });
        if (widget.onApproved != null) {
          widget.onApproved!();
        }
      }
    } catch (e) {
      debugPrint("Approve batch error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Approval failed: $e"),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      client.close();
      if (mounted) setState(() => _isApproving = false);
    }
  }

  Widget _buildReconciliationCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final calculatedTotal = _calculateTotalCost();
    final invoiceVal = _invoiceTotal ?? 0.0;
    final double diff = (invoiceVal - calculatedTotal).abs();
    final bool isReconciled = _invoiceTotal != null && diff < 0.1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: GlassBox(
        blur: 20,
        opacity: 0.15,
        border: Border.all(
          color: isReconciled 
              ? AppColors.success.withOpacity(0.4) 
              : (_invoiceTotal == null ? AppColors.warning.withOpacity(0.4) : AppColors.error.withOpacity(0.5)),
          width: 1.5,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Financial Reconciliation",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white : AppColors.lightOnSurface,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isReconciled
                          ? AppColors.success.withOpacity(0.15)
                          : (_invoiceTotal == null ? AppColors.warning.withOpacity(0.15) : AppColors.error.withOpacity(0.15)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isReconciled 
                          ? "MATCHED" 
                          : (_invoiceTotal == null ? "NO TOTAL SET" : "MISMATCH"),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isReconciled
                            ? AppColors.success
                            : (_invoiceTotal == null ? AppColors.warning : AppColors.error),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Calculated Cost Sum",
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "₹${calculatedTotal.toStringAsFixed(2)}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: isDark ? Colors.white : AppColors.lightOnSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: isDark ? Colors.white10 : Colors.black12,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Invoice Bill Total",
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (_isEditing)
                          SizedBox(
                            height: 32,
                            child: TextFormField(
                              controller: _invoiceTotalController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              decoration: InputDecoration(
                                prefixText: "₹ ",
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                border: const UnderlineInputBorder(),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: isReconciled ? AppColors.success : AppColors.primary),
                                ),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _invoiceTotal = double.tryParse(val);
                                });
                              },
                            ),
                          )
                        else
                          Text(
                            _invoiceTotal != null ? "₹${_invoiceTotal!.toStringAsFixed(2)}" : "Not Provided",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: _invoiceTotal != null 
                                  ? (isDark ? Colors.white : AppColors.lightOnSurface) 
                                  : AppColors.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (isReconciled)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Iconsax.tick_circle, color: AppColors.success, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Audit Verified: Item costs perfectly reconcile with the bill total.",
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (_invoiceTotal == null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Iconsax.warning_2, color: AppColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Invoice total is not set. Please enter the physical bill total to perform reconciliation.",
                          style: TextStyle(
                            color: isDark ? Colors.amber : Colors.amber.shade800,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Iconsax.warning_2, color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Valuation Mismatch: The calculated total cost (₹${calculatedTotal.toStringAsFixed(2)}) deviates from the bill total (₹${_invoiceTotal!.toStringAsFixed(2)}) by ₹${diff.toStringAsFixed(2)}. Please verify item quantities and cost prices.",
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_products.isEmpty) {
      return GlassBox(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text("No products found in proposal.", style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    double totalConfidence = 0.0;
    for (var p in _products) {
      totalConfidence += (p['confidence'] ?? 85.0).toDouble();
    }
    double avgConfidence = _products.isNotEmpty ? totalConfidence / _products.length : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title / Header bar
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0, right: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isApproved ? Iconsax.tick_circle : Iconsax.document_text,
                    color: _isApproved 
                        ? AppColors.success 
                        : (_isEditing ? AppColors.warning : AppColors.primary),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isApproved 
                        ? "Added to Inventory (${_products.length} items)" 
                        : (_isEditing ? "Review & Edit Proposal (${_products.length} items)" : "Bulk Product Proposal (${_products.length} items)"),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (!_isApproved)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isEditing = !_isEditing;
                      if (_isEditing) {
                        _initControllers();
                      } else {
                        _disposeControllers();
                      }
                    });
                  },
                  icon: Icon(
                    _isEditing ? Iconsax.close_circle : Iconsax.edit,
                    color: _isEditing ? AppColors.error : AppColors.primary,
                    size: 20,
                  ),
                  tooltip: _isEditing ? "Cancel Editing" : "Edit Proposal",
                ),
            ],
          ),
        ),

        // Extraction statistics row
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0, left: 4.0, right: 4.0),
          child: Row(
            children: [
              Expanded(
                child: GlassBox(
                  blur: 10,
                  opacity: 0.08,
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Iconsax.box_add, color: AppColors.primary, size: 14),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "EXTRACTED PRODUCTS",
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "${_products.length} Items",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : AppColors.lightOnSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassBox(
                  blur: 10,
                  opacity: 0.08,
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: (avgConfidence >= 80
                                    ? AppColors.success
                                    : (avgConfidence >= 50 ? Colors.orange : AppColors.error))
                                .withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Iconsax.cpu,
                            color: avgConfidence >= 80
                                ? AppColors.success
                                : (avgConfidence >= 50 ? Colors.orange : AppColors.error),
                            size: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "AVG AI CONFIDENCE",
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "${avgConfidence.toStringAsFixed(0)}%",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: avgConfidence >= 80
                                      ? AppColors.success
                                      : (avgConfidence >= 50 ? Colors.orange : AppColors.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Financial Reconciliation Status Card
        _buildReconciliationCard(),

        // Product Cards List
        ...List.generate(_products.length, (index) {
          final product = _products[index];
          final name = product['name'] ?? product['item_name'] ?? "Unnamed Item";
          final price = (product['price'] ?? product['price_per_unit'] ?? 0.0).toDouble();
          final costPrice = (product['cost_price'] ?? product['cp'] ?? 0.0).toDouble();
          final stock = (product['stock_quantity'] ?? product['quantity'] ?? 0).toInt();
          final category = product['category'] ?? "General";
          final isRestock = product['is_restock'] == true;

          // AI Confidence & Uncertainty indicators
          final confidence = (product['confidence'] ?? 85.0).toDouble();
          final uncertainFields = List<String>.from(product['uncertain_fields'] ?? []);
          final hasAlert = confidence < 75.0 || uncertainFields.isNotEmpty;

          final themeColor = isRestock ? AppColors.warning : AppColors.success;
          final lightThemeColorSoft = isRestock ? Colors.amber.shade600.withOpacity(0.1) : AppColors.lightPrimarySoft;

          final isNameUncertain = uncertainFields.contains('name');
          final isCategoryUncertain = uncertainFields.contains('category');
          final isQtyUncertain = uncertainFields.contains('stock_quantity') || uncertainFields.contains('quantity');
          final isUnitUncertain = uncertainFields.contains('unit');
          final isCostUncertain = uncertainFields.contains('cost_price') || uncertainFields.contains('cp');
          final isPriceUncertain = uncertainFields.contains('price') || uncertainFields.contains('selling_price');

          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: GlassBox(
              blur: 20,
              opacity: 0.1,
              border: Border.all(
                color: _isApproved 
                    ? AppColors.success.withOpacity(0.3) 
                    : (hasAlert
                        ? AppColors.error.withOpacity(0.7)
                        : (isRestock 
                            ? AppColors.warning.withOpacity(0.4) 
                            : AppColors.primary.withOpacity(0.3))),
                width: (isRestock || hasAlert) ? 1.5 : 1.0,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Restock/New Tag Header & AI Confidence
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: themeColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: themeColor.withOpacity(0.3), width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isRestock ? Iconsax.refresh : Iconsax.box,
                                      color: themeColor,
                                      size: 10,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isRestock ? "RESTOCK" : "NEW PRODUCT",
                                      style: TextStyle(
                                        color: themeColor,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (confidence >= 80
                                      ? AppColors.success
                                      : (confidence >= 50 ? Colors.orange : AppColors.error)).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: (confidence >= 80
                                        ? AppColors.success
                                        : (confidence >= 50 ? Colors.orange : AppColors.error)).withOpacity(0.25),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  "AI Confidence: ${confidence.toStringAsFixed(0)}%",
                                  style: TextStyle(
                                    color: confidence >= 80
                                        ? AppColors.success
                                        : (confidence >= 50 ? Colors.orange : AppColors.error),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasAlert)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.error.withOpacity(0.3), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Iconsax.warning_2, color: AppColors.error, size: 10),
                                SizedBox(width: 4),
                                Text(
                                  "NEEDS REVIEW",
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (isRestock)
                          Text(
                            "Already in Catalog",
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.warning.withOpacity(0.8),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // High Alert Warning Banner
                    if (hasAlert) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.error.withOpacity(0.3), width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Iconsax.warning_2, color: AppColors.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "HIGH ALERT: VERIFY DETAILS",
                                    style: TextStyle(
                                      color: AppColors.error,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    uncertainFields.isNotEmpty
                                        ? "AI is uncertain about: ${uncertainFields.join(', ')}."
                                        : "Low confidence extraction. Please verify all fields.",
                                    style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.black87,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_isEditing && !_isApproved) ...[
                              const SizedBox(width: 8),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  backgroundColor: AppColors.error.withOpacity(0.15),
                                  foregroundColor: AppColors.error,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                icon: const Icon(Iconsax.edit_2, size: 12),
                                label: const Text(
                                  "Edit Now",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isEditing = true;
                                    _initControllers();
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // Content Area
                    if (_isEditing) ...[
                      // Editable Mode UI
                      TextFormField(
                        controller: _nameControllers[index],
                        decoration: InputDecoration(
                          labelText: "Product Name",
                          prefixIcon: const Icon(Iconsax.box, size: 18),
                          enabledBorder: isNameUncertain
                              ? const OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.error, width: 1.5),
                                )
                              : null,
                          focusedBorder: isNameUncertain
                              ? const OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.error, width: 2.0),
                                )
                              : null,
                          labelStyle: isNameUncertain ? const TextStyle(color: AppColors.error) : null,
                          helperText: isNameUncertain ? "⚠️ Verify name on the invoice" : null,
                          helperStyle: isNameUncertain ? const TextStyle(color: AppColors.error, fontSize: 10) : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _categoryControllers[index],
                              decoration: InputDecoration(
                                labelText: "Category",
                                prefixIcon: const Icon(Iconsax.tag, size: 18),
                                enabledBorder: isCategoryUncertain
                                    ? const OutlineInputBorder(
                                        borderSide: BorderSide(color: AppColors.error, width: 1.5),
                                      )
                                    : null,
                                focusedBorder: isCategoryUncertain
                                    ? const OutlineInputBorder(
                                        borderSide: BorderSide(color: AppColors.error, width: 2.0),
                                      )
                                    : null,
                                labelStyle: isCategoryUncertain ? const TextStyle(color: AppColors.error) : null,
                                helperText: isCategoryUncertain ? "⚠️ Verify category" : null,
                                helperStyle: isCategoryUncertain ? const TextStyle(color: AppColors.error, fontSize: 10) : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: () {
                                    final currentVal = int.tryParse(_qtyControllers[index].text) ?? 0;
                                    if (currentVal > 1) {
                                      setState(() {
                                        _qtyControllers[index].text = (currentVal - 1).toString();
                                      });
                                    }
                                  },
                                  icon: const Icon(Iconsax.minus_cirlce, size: 20),
                                  color: AppColors.error,
                                ),
                                Expanded(
                                  child: TextFormField(
                                    controller: _qtyControllers[index],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    onChanged: (val) {
                                      setState(() {});
                                    },
                                    decoration: InputDecoration(
                                      labelText: "Quantity",
                                      contentPadding: EdgeInsets.zero,
                                      enabledBorder: isQtyUncertain
                                          ? const UnderlineInputBorder(
                                              borderSide: BorderSide(color: AppColors.error, width: 1.5),
                                            )
                                          : null,
                                      focusedBorder: isQtyUncertain
                                          ? const UnderlineInputBorder(
                                              borderSide: BorderSide(color: AppColors.error, width: 2.0),
                                            )
                                          : null,
                                      labelStyle: isQtyUncertain ? const TextStyle(color: AppColors.error) : null,
                                      helperText: isQtyUncertain ? "⚠️ Verify qty" : null,
                                      helperStyle: isQtyUncertain ? const TextStyle(color: AppColors.error, fontSize: 10) : null,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    final currentVal = int.tryParse(_qtyControllers[index].text) ?? 0;
                                    setState(() {
                                      _qtyControllers[index].text = (currentVal + 1).toString();
                                    });
                                  },
                                  icon: const Icon(Iconsax.add_circle, size: 20),
                                  color: AppColors.success,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedUnits[index],
                              decoration: InputDecoration(
                                labelText: "Unit",
                                prefixIcon: const Icon(Iconsax.weight, size: 18),
                                enabledBorder: isUnitUncertain
                                    ? const OutlineInputBorder(
                                        borderSide: BorderSide(color: AppColors.error, width: 1.5),
                                      )
                                    : null,
                                focusedBorder: isUnitUncertain
                                    ? const OutlineInputBorder(
                                        borderSide: BorderSide(color: AppColors.error, width: 2.0),
                                      )
                                    : null,
                                labelStyle: isUnitUncertain ? const TextStyle(color: AppColors.error) : null,
                                helperText: isUnitUncertain ? "⚠️ Verify unit" : null,
                                helperStyle: isUnitUncertain ? const TextStyle(color: AppColors.error, fontSize: 10) : null,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'pcs', child: Text('pcs')),
                                DropdownMenuItem(value: 'box', child: Text('box')),
                                DropdownMenuItem(value: 'dozen', child: Text('dozen')),
                                DropdownMenuItem(value: 'packet', child: Text('packet')),
                                DropdownMenuItem(value: 'kg', child: Text('kg')),
                                DropdownMenuItem(value: 'g', child: Text('g')),
                                DropdownMenuItem(value: 'ltr', child: Text('ltr')),
                                DropdownMenuItem(value: 'ml', child: Text('ml')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedUnits[index] = val;
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _costPriceControllers[index],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: "Cost Price",
                                prefixText: "₹ ",
                                enabledBorder: isCostUncertain
                                    ? const OutlineInputBorder(
                                        borderSide: BorderSide(color: AppColors.error, width: 1.5),
                                      )
                                    : null,
                                focusedBorder: isCostUncertain
                                    ? const OutlineInputBorder(
                                        borderSide: BorderSide(color: AppColors.error, width: 2.0),
                                      )
                                    : null,
                                labelStyle: isCostUncertain ? const TextStyle(color: AppColors.error) : null,
                                helperText: isCostUncertain ? "⚠️ Verify cost" : null,
                                helperStyle: isCostUncertain ? const TextStyle(color: AppColors.error, fontSize: 10) : null,
                              ),
                              onChanged: (val) {
                                final cp = double.tryParse(val) ?? 0.0;
                                final pct = double.tryParse(_profitPercentControllers[index].text) ?? 0.0;
                                final sp = cp * (1 + pct / 100.0);
                                _priceControllers[index].text = sp.toStringAsFixed(2);
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _profitPercentControllers[index],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: "Profit %",
                                suffixText: "%",
                              ),
                              onChanged: (val) {
                                final pct = double.tryParse(val) ?? 0.0;
                                final cp = double.tryParse(_costPriceControllers[index].text) ?? 0.0;
                                final sp = cp * (1 + pct / 100.0);
                                _priceControllers[index].text = sp.toStringAsFixed(2);
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _priceControllers[index],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: "Selling Price",
                                prefixText: "₹ ",
                                enabledBorder: isPriceUncertain
                                    ? const OutlineInputBorder(
                                        borderSide: BorderSide(color: AppColors.error, width: 1.5),
                                      )
                                    : null,
                                focusedBorder: isPriceUncertain
                                    ? const OutlineInputBorder(
                                        borderSide: BorderSide(color: AppColors.error, width: 2.0),
                                      )
                                    : null,
                                labelStyle: isPriceUncertain ? const TextStyle(color: AppColors.error) : null,
                                helperText: isPriceUncertain ? "⚠️ Verify price" : null,
                                helperStyle: isPriceUncertain ? const TextStyle(color: AppColors.error, fontSize: 10) : null,
                              ),
                              onChanged: (val) {
                                final sp = double.tryParse(val) ?? 0.0;
                                final cp = double.tryParse(_costPriceControllers[index].text) ?? 0.0;
                                if (cp > 0) {
                                  final pct = ((sp - cp) / cp) * 100.0;
                                  _profitPercentControllers[index].text = pct.toStringAsFixed(1);
                                }
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // Static Mode UI
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: themeColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isRestock ? Iconsax.refresh : Iconsax.box, 
                              color: themeColor,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  category,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "₹${price.toStringAsFixed(2)}",
                                style: TextStyle(
                                  color: themeColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (costPrice > 0) ...[
                                    Text(
                                      "CP: ₹${costPrice.toStringAsFixed(0)}",
                                      style: TextStyle(
                                        color: isDark ? Colors.white54 : Colors.black54,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: stock > 0 ? themeColor.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      stock > 0 
                                          ? (isRestock 
                                              ? "+$stock ${product['unit'] ?? 'pcs'} stock" 
                                              : "$stock ${product['unit'] ?? 'pcs'} proposed")
                                          : "No stock",
                                      style: TextStyle(
                                        color: stock > 0 ? themeColor : AppColors.error,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),

        // Action Buttons Row (Save Draft, Approve, etc.)
        if (!_isApproved)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                if (_isEditing) ...[
                  // Cancel Edit Button
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _isEditing = false;
                          _disposeControllers();
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                      ),
                      icon: const Icon(Iconsax.close_circle, color: AppColors.error, size: 18),
                      label: const Text(
                        "Cancel", 
                        style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Save Draft Button
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      onPressed: _isSavingDraft ? null : _saveDraft,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                      ),
                      icon: _isSavingDraft
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                            )
                          : const Icon(Iconsax.document_filter, color: AppColors.primary, size: 18),
                      label: const Text(
                        "Save Draft", 
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Approve & Import Button
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isApproving ? null : _approveBatch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isApproving
                            ? const SizedBox(
                                height: 20, 
                                width: 20, 
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Iconsax.add_square, color: Colors.white, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Approve & Import", 
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Colors.white, 
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ] else ...[
                  // Approve Batch Button
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isApproving ? null : _approveBatch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isApproving
                            ? const SizedBox(
                                height: 20, 
                                width: 20, 
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Iconsax.add_square, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Approve & Import", 
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Colors.white, 
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2),
      ],
    ).animate().fadeIn().slideX(begin: 0.1);
  }
}
