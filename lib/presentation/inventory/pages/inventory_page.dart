import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../core/session.dart';
import '../../main/pages/main_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_box.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/responsive_layout.dart';
import 'package:dukansathi_new/models/product.dart';
import '../providers/inventory_provider.dart';
import '../../../core/config.dart';
import '../../chat/widgets/inventory_draft_card.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    Future.microtask(() {
      ref.read(inventoryProvider.notifier).fetchProducts();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(inventoryProvider.notifier).loadMoreProducts();
    }
  }

  Future<void> _fetchProducts() async {
    await ref.read(inventoryProvider.notifier).fetchProducts(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                state.isLoading 
                    ? const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SkeletonSummaryCard()) 
                    : _buildValuationCard(state.totalValue, state.totalRetailValue),
                if (!state.isLoading && state.allProducts.isNotEmpty) _buildCategoryFilters(state),
                const SizedBox(height: 10),
                Expanded(
                  child: state.isLoading
                      ? _buildListSkeleton()
                      : state.displayedProducts.isEmpty
                          ? _buildEmptyState()
                          : _buildProductList(state),
                ),
                const SizedBox(height: 80), // padding for bottom bar
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0), // Above bottom nav
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Bulk Import FAB
            FloatingActionButton.extended(
              heroTag: 'btnBulkImport',
              onPressed: () => _showBulkImportOptions(),
              backgroundColor: AppColors.warning,
              icon: const Icon(Iconsax.document_upload, color: Colors.white),
              label: const Text(
                "Bulk Import", 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ).animate().scale(delay: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 12),
            // Manual Add FAB
            FloatingActionButton.extended(
              heroTag: 'btnManualAdd',
              onPressed: () => _showProductForm(),
              backgroundColor: AppColors.primary,
              icon: const Icon(Iconsax.add, color: Colors.white),
              label: const Text(
                "Add Product", 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ).animate().scale(delay: 500.ms, curve: Curves.easeOutBack),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final isDesktop = ResponsiveLayout.isDesktop(context) || ResponsiveLayout.isTablet(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (!isDesktop) ...[
                IconButton(
                  icon: const Icon(Iconsax.menu, size: 24),
                  onPressed: () => mainScaffoldKey.currentState?.openDrawer(),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                "Inventory",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ],
          ),
          ref.watch(inventoryProvider).isLoading
              ? SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).iconTheme.color ?? Colors.white),
                      ),
                    ),
                  ),
                )
              : IconButton(
                  onPressed: _fetchProducts,
                  icon: Icon(Iconsax.refresh, color: Theme.of(context).iconTheme.color),
                ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      title: "No Products Found",
      subtitle: "Ask Dukan Sathi AI to add products or sync your inventory.",
      icon: Iconsax.box_search,
      actionLabel: "Refresh Inventory",
      onAction: _fetchProducts,
    );
  }

  Widget _buildListSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: 6,
      itemBuilder: (context, index) => const SkeletonListTile(),
    );
  }

  Widget _buildValuationCard(double totalValue, double totalRetailValue) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassBox(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Total Asset (Cost)", 
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "₹${totalValue.toStringAsFixed(0)}",
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: isDark ? Colors.white10 : Colors.black12,
                      margin: const EdgeInsets.symmetric(horizontal: 15),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Retail Value", 
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "₹${totalRetailValue.toStringAsFixed(0)}",
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.8),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.primary.withOpacity(0.15) : AppColors.lightPrimarySoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Iconsax.chart_2, color: isDark ? AppColors.primary : AppColors.lightPrimary),
              ),
            ],
          ),
        ),
      ).animate().slideY(begin: 0.2, curve: Curves.easeOut).fadeIn(),
    );
  }

  Widget _buildCategoryFilters(InventoryState state) {
    return Container(
      height: 60,
      margin: const EdgeInsets.only(top: 20),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: state.categories.length,
        itemBuilder: (context, index) {
          final cat = state.categories[index];
          final isSelected = state.selectedCategory == cat;
          final isLowStock = cat == 'Low Stock';
          
          return GestureDetector(
            onTap: () {
              ref.read(inventoryProvider.notifier).selectCategory(cat);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected 
                    ? (isLowStock ? AppColors.error : (Theme.of(context).brightness == Brightness.dark ? AppColors.primary : AppColors.lightPrimary))
                    : Theme.of(context).cardColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Theme.of(context).dividerColor.withOpacity(0.1),
                ),
              ),
              alignment: Alignment.center,
              child: Row(
                children: [
                  if (isLowStock) ...[
                    const Icon(Iconsax.warning_2, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    cat,
                    style: TextStyle(
                      color: isSelected 
                          ? Colors.white 
                          : Theme.of(context).textTheme.bodyMedium?.color,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(delay: (index * 50).ms);
        },
      ),
    );
  }

  Future<void> _restockProduct(Product product) async {
    final productId = product.id;
    final productName = product.name;
    const adjustAmount = 10;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Restocked +10 for $productName', style: const TextStyle(color: Colors.white)),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      await ref.read(inventoryProvider.notifier).adjustStock(productId, adjustAmount);
      debugPrint('[Inventory] Optimistic restock confirmed for $productName');
    } catch (e) {
      debugPrint('[Inventory] Optimistic restock failed: $e');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to restock $productName.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildProductList(InventoryState state) {
    if (state.displayedProducts.isEmpty) {
      return Center(
        child: Text("No products in '${state.selectedCategory}'", style: const TextStyle(color: Colors.white54)),
      );
    }
    
    final isDesktop = ResponsiveLayout.isDesktop(context);
    final isTablet = ResponsiveLayout.isTablet(context);

    if (isDesktop || isTablet) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = isDesktop ? 3 : 2;
          final cardWidth = (width - (crossAxisCount - 1) * 15) / crossAxisCount;
          const double cardHeight = 100.0;
          final double childAspectRatio = cardWidth / cardHeight;

          return GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: childAspectRatio,
            ),
            itemCount: state.displayedProducts.length + (state.isLoadingMore ? crossAxisCount : 0),
            itemBuilder: (context, index) {
              if (index >= state.displayedProducts.length) {
                if (index == state.displayedProducts.length + (crossAxisCount ~/ 2)) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  );
                }
                return const SizedBox.shrink();
              }
              return _buildProductCard(state.displayedProducts[index], index);
            },
          );
        },
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: state.displayedProducts.length + (state.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.displayedProducts.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            ),
          );
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 15),
          child: _buildProductCard(state.displayedProducts[index], index),
        );
      },
    );
  }

  Widget _buildProductCard(Product product, int index) {
    final name = product.name;
    final price = product.price;
    final stock = product.stockQuantity;
    final category = product.category.isEmpty ? 'General' : product.category;
    final isLowStock = stock < 10;

    return Dismissible(
      key: Key(product.id),
      direction: DismissDirection.endToStart,
      background: Container(
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppColors.primary.withOpacity(0.3) : AppColors.lightPrimary.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text("Restock +10", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(width: 10),
            Icon(Iconsax.add_circle, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        await _restockProduct(product);
        return false; // don't remove from list
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: isLowStock ? [
            BoxShadow(color: AppColors.error.withOpacity(0.2), blurRadius: 15, spreadRadius: 2)
          ] : null,
        ),
        child: GlassBox(
          child: ListTile(
            onTap: () => _showProductForm(product: product),
            contentPadding: const EdgeInsets.all(15),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isLowStock 
                    ? AppColors.error.withOpacity(0.1) 
                    : (Theme.of(context).brightness == Brightness.dark ? AppColors.primary.withOpacity(0.1) : AppColors.lightPrimarySoft),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Iconsax.box, color: isLowStock ? AppColors.error : (Theme.of(context).brightness == Brightness.dark ? AppColors.primary : AppColors.lightPrimary)),
            ),
            title: Text(
              name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              category,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "₹${price.toStringAsFixed(0)}",
                  style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  "Stock: $stock ${product.unit}",
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isLowStock ? AppColors.error : Theme.of(context).textTheme.bodySmall?.color,
                    fontWeight: isLowStock ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().slideY(begin: 0.1, delay: (index * 50).ms).fadeIn();
  }

  void _showProductForm({Product? product}) {
    final isEdit = product != null;
    final nameController = TextEditingController(text: isEdit ? product.name : '');
    final categoryController = TextEditingController(text: isEdit ? product.category : '');
    final priceController = TextEditingController(text: isEdit ? product.price.toString() : '');
    final costPriceController = TextEditingController(text: isEdit ? product.costPrice.toString() : '');
    final stockController = TextEditingController(text: isEdit ? product.stockQuantity.toString() : '');
    final barcodeController = TextEditingController(text: isEdit ? product.barcode ?? '' : '');
    double selectedGst = isEdit ? product.gstRate : 0.0;
    String selectedUnit = isEdit ? product.unit : 'pcs';

    double initialProfit = 0.0;
    if (isEdit && product.costPrice > 0) {
      initialProfit = ((product.price - product.costPrice) / product.costPrice) * 100.0;
    }
    final profitPercentController = TextEditingController(
      text: initialProfit > 0 ? initialProfit.toStringAsFixed(1) : '0.0',
    );
    
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              border: Border.all(color: isDark ? AppColors.darkGlassBorder : AppColors.lightGlassBorder),
            ),
            padding: const EdgeInsets.all(30),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isEdit ? "Edit Product Details" : "Add New Product",
                        style: TextStyle(
                          color: isDark ? Colors.white : AppColors.lightOnSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: isDark ? Colors.white54 : Colors.black54),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text("Product Name *", style: TextStyle(color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  GlassBox(
                    child: TextField(
                      controller: nameController,
                      style: TextStyle(color: isDark ? Colors.white : AppColors.lightOnSurface),
                      decoration: InputDecoration(
                        hintText: "Enter product name",
                        hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Cost Price (INR) *", style: TextStyle(color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            GlassBox(
                              child: TextField(
                                controller: costPriceController,
                                keyboardType: TextInputType.number,
                                style: TextStyle(color: isDark ? Colors.white : AppColors.lightOnSurface),
                                decoration: InputDecoration(
                                  hintText: "0.00",
                                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                ),
                                onChanged: (val) {
                                  final cp = double.tryParse(val) ?? 0.0;
                                  final pct = double.tryParse(profitPercentController.text) ?? 0.0;
                                  final sp = cp * (1 + pct / 100.0);
                                  priceController.text = sp.toStringAsFixed(2);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Profit Margin (%)", style: TextStyle(color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            GlassBox(
                              child: TextField(
                                controller: profitPercentController,
                                keyboardType: TextInputType.number,
                                style: TextStyle(color: isDark ? Colors.white : AppColors.lightOnSurface),
                                decoration: InputDecoration(
                                  hintText: "0.0",
                                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                ),
                                onChanged: (val) {
                                  final pct = double.tryParse(val) ?? 0.0;
                                  final cp = double.tryParse(costPriceController.text) ?? 0.0;
                                  final sp = cp * (1 + pct / 100.0);
                                  priceController.text = sp.toStringAsFixed(2);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Selling Price (INR) *", style: TextStyle(color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            GlassBox(
                              child: TextField(
                                controller: priceController,
                                keyboardType: TextInputType.number,
                                style: TextStyle(color: isDark ? Colors.white : AppColors.lightOnSurface),
                                decoration: InputDecoration(
                                  hintText: "0.00",
                                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                ),
                                onChanged: (val) {
                                  final sp = double.tryParse(val) ?? 0.0;
                                  final cp = double.tryParse(costPriceController.text) ?? 0.0;
                                  if (cp > 0) {
                                    final pct = ((sp - cp) / cp) * 100.0;
                                    profitPercentController.text = pct.toStringAsFixed(1);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Stock Quantity *", style: TextStyle(color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            GlassBox(
                              child: TextField(
                                controller: stockController,
                                keyboardType: TextInputType.number,
                                style: TextStyle(color: isDark ? Colors.white : AppColors.lightOnSurface),
                                decoration: InputDecoration(
                                  hintText: "0",
                                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Unit *", style: TextStyle(color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 15),
                              height: 52,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? AppColors.darkGlassBorder : AppColors.lightGlassBorder),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedUnit,
                                  dropdownColor: isDark ? AppColors.darkSurface : AppColors.lightBackground,
                                  style: TextStyle(color: isDark ? Colors.white : AppColors.lightOnSurface, fontSize: 16),
                                  icon: Icon(Icons.arrow_drop_down, color: isDark ? Colors.white70 : Colors.black54),
                                  isExpanded: true,
                                  items: ['pcs', 'box', 'dozen', 'kg', 'g', 'l', 'ml'].map((u) {
                                    return DropdownMenuItem<String>(
                                      value: u,
                                      child: Text(u),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setSheetState(() {
                                        selectedUnit = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Category *", style: TextStyle(color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            GlassBox(
                              child: TextField(
                                controller: categoryController,
                                style: TextStyle(color: isDark ? Colors.white : AppColors.lightOnSurface),
                                decoration: InputDecoration(
                                  hintText: "General, Groceries...",
                                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("GST Rate *", style: TextStyle(color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 15),
                              height: 52,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? AppColors.darkGlassBorder : AppColors.lightGlassBorder),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<double>(
                                  value: selectedGst,
                                  dropdownColor: isDark ? AppColors.darkSurface : AppColors.lightBackground,
                                  style: TextStyle(color: isDark ? Colors.white : AppColors.lightOnSurface, fontSize: 16),
                                  icon: Icon(Icons.arrow_drop_down, color: isDark ? Colors.white70 : Colors.black54),
                                  isExpanded: true,
                                  items: [0.0, 5.0, 12.0, 18.0, 28.0].map((rate) {
                                    return DropdownMenuItem<double>(
                                      value: rate,
                                      child: Text("${rate.toStringAsFixed(0)}%"),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setSheetState(() {
                                        selectedGst = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Barcode (Optional)", style: TextStyle(color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            GlassBox(
                              child: TextField(
                                controller: barcodeController,
                                style: TextStyle(color: isDark ? Colors.white : AppColors.lightOnSurface),
                                decoration: InputDecoration(
                                  hintText: "Scan/Enter code",
                                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 35),
                  Row(
                    children: [
                      if (isEdit) ...[
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _confirmDeleteProduct(product);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("Delete", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 15),
                      ],
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () async {
                            final name = nameController.text.trim();
                            final cat = categoryController.text.trim().isEmpty ? 'General' : categoryController.text.trim();
                            final price = double.tryParse(priceController.text.trim()) ?? -1.0;
                            final costPrice = double.tryParse(costPriceController.text.trim()) ?? 0.0;
                            final stock = int.tryParse(stockController.text.trim()) ?? -1;
                            final barcode = barcodeController.text.trim().isEmpty ? null : barcodeController.text.trim();

                            if (name.isEmpty || price < 0 || stock < 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Please fill all required fields correctly"), backgroundColor: AppColors.warning),
                              );
                              return;
                            }
                            Navigator.pop(context);

                            final shopId = UserSession().shopId ?? '';
                            final newProduct = Product(
                              id: isEdit ? product.id : const Uuid().v4(),
                              shopId: shopId,
                              name: name,
                              price: price,
                              stockQuantity: stock,
                              category: cat,
                              costPrice: costPrice,
                              gstRate: selectedGst,
                              barcode: barcode,
                              unit: selectedUnit,
                            );

                            if (isEdit) {
                              await ref.read(inventoryProvider.notifier).updateProduct(newProduct);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Product updated successfully!"), backgroundColor: AppColors.success),
                              );
                            } else {
                              await ref.read(inventoryProvider.notifier).addProduct(newProduct);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Product added successfully!"), backgroundColor: AppColors.success),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(isEdit ? "Save Changes" : "Add Product", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteProduct(Product product) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        bool isConfirmed = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Iconsax.warning_2, color: AppColors.error, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    "Permanently Delete?",
                    style: TextStyle(
                      color: isDark ? Colors.white : AppColors.lightOnSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Are you sure you want to delete ${product.name}? This will remove it completely from your stock list and sales database forever.",
                    style: TextStyle(
                      color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),
                  InkWell(
                    onTap: () {
                      setDialogState(() {
                        isConfirmed = !isConfirmed;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isConfirmed,
                            activeColor: AppColors.error,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (val) {
                              setDialogState(() {
                                isConfirmed = val ?? false;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "I confirm I want to permanently delete this product.",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white70 : AppColors.lightOnSurface.withOpacity(0.9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "Cancel",
                    style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                  ),
                ),
                ElevatedButton(
                  onPressed: isConfirmed
                      ? () async {
                          Navigator.pop(context); // close dialog
                          await ref.read(inventoryProvider.notifier).deleteProduct(product.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Product deleted successfully"),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    disabledBackgroundColor: isDark 
                        ? Colors.white.withOpacity(0.06) 
                        : Colors.black.withOpacity(0.06),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: Text(
                    "Permanently Delete",
                    style: TextStyle(
                      color: isConfirmed 
                          ? Colors.white 
                          : (isDark ? Colors.white30 : Colors.black38),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
  void _showBulkImportOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border.all(
            color: isDark ? AppColors.darkGlassBorder : AppColors.lightGlassBorder,
          ),
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Bulk Inventory Import",
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.lightOnSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: isDark ? Colors.white54 : Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Ingest dozens of products instantly. Choose your import source below to begin.",
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            // ── REAL: AI Photo Scan (Camera) ──────────────────────────────
            _buildImportOption(
              icon: Iconsax.camera,
              title: "Scan Bill with Camera",
              subtitle: "Point camera at a wholesale invoice — AI extracts all products instantly.",
              color: AppColors.success,
              badge: "AI",
              onTap: () {
                Navigator.pop(context);
                _scanInvoicePhoto(ImageSource.camera);
              },
            ),
            const SizedBox(height: 14),
            // ── REAL: AI Photo Scan (Gallery) ─────────────────────────────
            _buildImportOption(
              icon: Iconsax.gallery,
              title: "Import Bill from Gallery",
              subtitle: "Pick a saved photo of a vendor bill to auto-fill your inventory.",
              color: AppColors.primary,
              badge: "AI",
              onTap: () {
                Navigator.pop(context);
                _scanInvoicePhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 14),
            _buildImportOption(
              icon: Iconsax.document_text,
              title: "Import Excel / CSV Sheets",
              subtitle: "Perfect for distributor spreadsheets and catalog files.",
              color: AppColors.warning,
              onTap: () {
                Navigator.pop(context);
                _showImportPresetSelection("Excel / CSV Sheet");
              },
            ),
            const SizedBox(height: 14),
            _buildImportOption(
              icon: Iconsax.document,
              title: "Import PDF Invoices",
              subtitle: "Ingest products directly from structured vendor bills.",
              color: Colors.grey,
              onTap: () {
                Navigator.pop(context);
                _showImportPresetSelection("PDF Invoice");
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Opens camera or gallery, sends image to AI vision API, then proposes batch.
  Future<void> _scanInvoicePhoto(ImageSource source) async {
    final picker = ImagePicker();
    XFile? pickedFile;

    try {
      pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 1200,
        maxHeight: 1200,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not access camera/gallery: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (pickedFile == null) return; // user cancelled

    // Show extraction loading dialog
    if (!mounted) return;
    _showAiExtractionDialog(pickedFile);
  }

  void _showAiExtractionDialog(XFile imageFile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String currentStep = "Reading invoice image...";
    double progress = 0.1;
    String? errorMessage;
    bool _started = false; // closure guard — ensures pipeline runs exactly once

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Kick off the real async pipeline exactly once
          if (!_started) {
            _started = true;
            Future.microtask(() async {
              try {
                // Step 1: Read & encode image
                setDialogState(() { currentStep = "Encoding image for AI..."; progress = 0.2; });
                final bytes = await imageFile.readAsBytes();
                final base64Image = base64Encode(bytes);
                final mimeType = imageFile.mimeType ?? 'image/jpeg';

                // Step 2: Call NVIDIA vision API
                setDialogState(() { currentStep = "AI is reading your bill...\n(Llama Vision Model)"; progress = 0.45; });

                // Animate progress smoothly while waiting for AI response
                bool awaitingAi = true;
                final aiSteps = [
                  "AI is reading your bill...",
                  "Analyzing line items...",
                  "Extracting product details...",
                  "Almost there...",
                ];
                int stepIdx = 0;
                () async {
                  while (awaitingAi) {
                    await Future.delayed(const Duration(seconds: 4));
                    if (awaitingAi && dialogContext.mounted) {
                      stepIdx = (stepIdx + 1).clamp(0, aiSteps.length - 1);
                      if (progress < 0.75) {
                        setDialogState(() {
                          progress += 0.02;
                          currentStep = aiSteps[stepIdx];
                        });
                      }
                    }
                  }
                }();

                final extractResponse = await http.post(
                  AppConfig.getApiUri('/api/extract-bill-image'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'imageBase64': base64Image,
                    'mimeType': mimeType,
                  }),
                ).timeout(const Duration(seconds: 120));
                awaitingAi = false;

                if (extractResponse.statusCode != 200) {
                  final errBody = jsonDecode(extractResponse.body);
                  throw Exception(errBody['error'] ?? 'AI extraction failed (${extractResponse.statusCode})');
                }

                final extractData = jsonDecode(extractResponse.body) as Map<String, dynamic>;
                final products = (extractData['products'] as List<dynamic>)
                    .map((p) => Map<String, dynamic>.from(p as Map))
                    .toList();

                if (products.isEmpty) {
                  throw Exception('No products found in this image. Try a clearer photo.');
                }

                // Step 3: Propose batch
                setDialogState(() { currentStep = "Creating inventory draft...\n${products.length} products found!"; progress = 0.8; });
                final proposeResponse = await http.post(
                  AppConfig.getApiUri('/api/propose-batch'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'products': products,
                    'userIdentifier': UserSession().userId ?? 'web-user',
                    'shopId': UserSession().shopId ?? '',
                  }),
                );

                if (proposeResponse.statusCode != 200) {
                  throw Exception('Failed to create draft batch');
                }

                final proposeData = jsonDecode(proposeResponse.body) as Map<String, dynamic>;
                if (proposeData['success'] != true) {
                  throw Exception(proposeData['message'] ?? 'Failed to propose batch');
                }

                setDialogState(() { currentStep = "Draft ready!"; progress = 1.0; });

                await Future.delayed(const Duration(milliseconds: 400));

                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) _showConfirmationDraftSheet(proposeData);

              } catch (e) {
                setDialogState(() {
                  errorMessage = e.toString().replaceFirst('Exception: ', '');
                  progress = 0.0;
                });
              }
            });
          }

          return AlertDialog(
            backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (errorMessage == null) ...[
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.success),
                            strokeWidth: 3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "AI Bill Scanner",
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.lightOnSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Powered by Llama Vision",
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      currentStep,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ] else ...[
                    const Icon(Iconsax.warning_2, color: AppColors.error, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      "Extraction Failed",
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.lightOnSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: const Text("Close", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    String? badge,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: GlassBox(
        blur: 10,
        opacity: 0.05,
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: isDark ? Colors.white : AppColors.lightOnSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Iconsax.arrow_right_1, color: isDark ? Colors.white30 : Colors.black38, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  void _showImportPresetSelection(String sourceType) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border.all(
            color: isDark ? AppColors.darkGlassBorder : AppColors.lightGlassBorder,
          ),
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Select Import Sample",
                  style: TextStyle(
                    color: isDark ? Colors.white : AppColors.lightOnSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: isDark ? Colors.white54 : Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Select a preset file template to demo Dukan Sathi's intelligent parser & restock detection system instantly.",
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            _buildPresetOption(
              title: "Distributor CSV Catalog (4 items)",
              subtitle: "Simulates importing an Excel/CSV spreadsheet from a hygiene distributor.",
              items: [
                {"name": "Dettol Liquid Handwash", "price": 99.0, "cost_price": 75.0, "stock_quantity": 50, "category": "Hygiene"},
                {"name": "Paracetamol 650mg", "price": 30.0, "cost_price": 18.0, "stock_quantity": 120, "category": "Pharmacy"},
                {"name": "Tata Salt 1kg", "price": 28.0, "cost_price": 22.0, "stock_quantity": 40, "category": "Grocery"},
                {"name": "Maggi Noodles 2-Min", "price": 14.0, "cost_price": 11.0, "stock_quantity": 100, "category": "Grocery"},
              ],
            ),
            const SizedBox(height: 12),
            _buildPresetOption(
              title: "Wholesaler Grocery Invoice PDF (4 items)",
              subtitle: "Simulates scanning structured billing records from a local wholesale vendor.",
              items: [
                {"name": "Fortune Soyabean Oil 1L", "price": 165.0, "cost_price": 140.0, "stock_quantity": 30, "category": "Grocery"},
                {"name": "Aashirvaad Atta 5kg", "price": 260.0, "cost_price": 215.0, "stock_quantity": 25, "category": "Grocery"},
                {"name": "Dettol Liquid Handwash", "price": 99.0, "cost_price": 75.0, "stock_quantity": 20, "category": "Hygiene"},
                {"name": "Colgate MaxFresh 150g", "price": 112.0, "cost_price": 90.0, "stock_quantity": 50, "category": "Hygiene"},
              ],
            ),
            const SizedBox(height: 12),
            _buildPresetOption(
              title: "Electronics Invoice Photo OCR (3 items)",
              subtitle: "Simulates using camera OCR to ingest electrical catalog items.",
              items: [
                {"name": "Syska LED Bulb 9W", "price": 140.0, "cost_price": 100.0, "stock_quantity": 60, "category": "Electronics"},
                {"name": "Syska LED Bulb 12W", "price": 180.0, "cost_price": 130.0, "stock_quantity": 40, "category": "Electronics"},
                {"name": "SanDisk 64GB Flash Drive", "price": 450.0, "cost_price": 320.0, "stock_quantity": 15, "category": "Electronics"},
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetOption({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        Navigator.pop(context); // Close selection sheet
        _runImportSimulation(title, items);
      },
      borderRadius: BorderRadius.circular(14),
      child: GlassBox(
        blur: 5,
        opacity: 0.04,
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDark ? Colors.white : AppColors.lightOnSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "${items.length} Items",
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _runImportSimulation(String presetName, List<Map<String, dynamic>> sampleProducts) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String currentStep = "Uploading file to server...";
    double progress = 0.2;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Simulate steps in sequence
          Future.delayed(const Duration(milliseconds: 800), () {
            if (context.mounted && currentStep == "Uploading file to server...") {
              setDialogState(() {
                currentStep = "Analyzing layout & extracting tabular data...";
                progress = 0.5;
              });
            }
          });

          Future.delayed(const Duration(milliseconds: 1600), () {
            if (context.mounted && currentStep == "Analyzing layout & extracting tabular data...") {
              setDialogState(() {
                currentStep = "Performing restock check against catalog...";
                progress = 0.8;
              });
            }
          });

          Future.delayed(const Duration(milliseconds: 2300), () async {
            if (context.mounted && currentStep == "Performing restock check against catalog...") {
              setDialogState(() {
                currentStep = "Finalizing draft product batch...";
                progress = 1.0;
              });

              // Make the actual call to Server to propose this product batch
              final client = http.Client();
              try {
                final response = await client.post(
                  AppConfig.getApiUri('/api/propose-batch'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'products': sampleProducts,
                    'userIdentifier': UserSession().userId ?? 'web-user',
                    'shopId': UserSession().shopId ?? 'default_shop',
                  }),
                );

                Navigator.pop(context); // Close loader dialog

                if (response.statusCode == 200) {
                  final resData = jsonDecode(response.body);
                  if (resData['success'] == true) {
                    _showConfirmationDraftSheet(resData);
                  } else {
                    throw Exception(resData['message'] ?? 'Failed to propose batch');
                  }
                } else {
                  throw Exception('Server returned ${response.statusCode}');
                }
              } catch (e) {
                Navigator.pop(context); // Close loader dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Error proposing batch: $e"),
                    backgroundColor: AppColors.error,
                  ),
                );
              } finally {
                client.close();
              }
            }
          });

          return AlertDialog(
            backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    height: 60,
                    width: 60,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      strokeWidth: 4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Parsing Import Source",
                    style: TextStyle(
                      color: isDark ? Colors.white : AppColors.lightOnSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    presetName,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    currentStep,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showConfirmationDraftSheet(Map<String, dynamic> batchPayload) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          border: Border.all(
            color: isDark ? AppColors.darkGlassBorder : AppColors.lightGlassBorder,
          ),
        ),
        padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 12),
        child: Column(
          children: [
            // Drawer line handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: InventoryDraftCard(
                  payload: batchPayload,
                  onApproved: () {
                    // Trigger inventory refresh immediately
                    ref.read(inventoryProvider.notifier).fetchProducts(forceRefresh: true);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

