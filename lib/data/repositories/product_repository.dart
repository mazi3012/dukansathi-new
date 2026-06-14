import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/database.dart';
import '../../core/services/connectivity_service.dart';
import '../../models/product.dart';
import '../local/local_database.dart';
import '../sync/sync_manager.dart';

class ProductRepository {
  final LocalDatabase _localDb = LocalDatabase.instance;
  final ConnectivityService _connectivity = ConnectivityService.instance;
  final SyncManager _syncManager = SyncManager.instance;

  /// Retrieves products from the local database. If online, triggers a background cloud sync.
  Future<List<Product>> getProducts(
    String shopId, {
    bool forceRefresh = false,
    int? limit,
    int? offset,
  }) async {
    // 1. Instantly return local cached products
    final localMaps = await _localDb.queryAll(
      'products',
      where: 'shop_id = ?',
      whereArgs: [shopId],
      orderBy: 'name ASC',
      limit: limit,
      offset: offset,
    );
    
    final localProducts = localMaps.map((m) {
      // Map integer from SQLite to boolean
      final map = Map<String, dynamic>.from(m);
      map['is_service'] = map['is_service'] == 1;
      
      // Parse metadata text back to map
      final metadataStr = map['metadata'] as String? ?? '{}';
      final metadataMap = jsonDecode(metadataStr) as Map<String, dynamic>;
      map['metadata'] = metadataMap;
      
      // Populate barcode field from metadata
      if (metadataMap.containsKey('barcode')) {
        map['barcode'] = metadataMap['barcode'];
      }
      
      return Product.fromJson(map);
    }).toList();

    // 2. Trigger background sync if online
    if (_connectivity.isOnline && (localProducts.isEmpty || forceRefresh)) {
      if (forceRefresh) {
        await syncProductsFromCloud(shopId);
        // Fetch again to return the fully synchronized fresh list
        final freshMaps = await _localDb.queryAll(
          'products',
          where: 'shop_id = ?',
          whereArgs: [shopId],
          orderBy: 'name ASC',
          limit: limit,
          offset: offset,
        );
        return freshMaps.map((m) {
          final map = Map<String, dynamic>.from(m);
          map['is_service'] = map['is_service'] == 1;
          final metadataStr = map['metadata'] as String? ?? '{}';
          final metadataMap = jsonDecode(metadataStr) as Map<String, dynamic>;
          map['metadata'] = metadataMap;
          if (metadataMap.containsKey('barcode')) {
            map['barcode'] = metadataMap['barcode'];
          }
          return Product.fromJson(map);
        }).toList();
      } else {
        // Perform background sync to refresh the local cache
        syncProductsFromCloud(shopId);
      }
    }

    return localProducts;
  }

  /// Fetches products from Supabase and populates the local cache
  Future<void> syncProductsFromCloud(String shopId) async {
    try {
      final cloudProducts = await supabase
          .from('products')
          .select('id, shop_id, name, price, stock_quantity, category, description, is_service, gst_rate, hsn_sac_code, barcode, cost_price, metadata, unit')
          .eq('shop_id', shopId);

      await _localDb.executeInTransaction((txn) async {
        // 1. Delete local products not present in cloud
        final cloudProductIds = cloudProducts.map((p) => p['id'] as String).toList();
        if (cloudProductIds.isNotEmpty) {
          final placeholders = List.filled(cloudProductIds.length, '?').join(',');
          await txn.delete(
            'products',
            where: 'shop_id = ? AND id NOT IN ($placeholders)',
            whereArgs: [shopId, ...cloudProductIds],
          );
        } else {
          await txn.delete(
            'products',
            where: 'shop_id = ?',
            whereArgs: [shopId],
          );
        }

        // 2. Insert/replace from cloud
        for (var p in cloudProducts) {
          final mapped = Map<String, dynamic>.from(p);
          mapped['is_service'] = (mapped['is_service'] == true) ? 1 : 0;
          
          // Inject barcode into the local metadata json block for compatibility
          final metadataMap = Map<String, dynamic>.from(mapped['metadata'] ?? {});
          if (mapped['barcode'] != null) {
            metadataMap['barcode'] = mapped['barcode'];
          }
          
          mapped['metadata'] = jsonEncode(metadataMap);

          await txn.insert(
            'products',
            mapped,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      debugPrint('[ProductRepository] Synced ${cloudProducts.length} products to local DB.');
    } catch (e) {
      debugPrint('[ProductRepository] Cloud fetch failed: $e');
    }
  }

  /// Fetches a product instantly by barcode, utilizing local cache or cloud
  Future<Product?> getProductByBarcode(String shopId, String barcode) async {
    // 1. Check local DB first using fast barcode column query
    final localMaps = await _localDb.queryAll(
      'products',
      where: "shop_id = ? AND barcode = ?",
      whereArgs: [shopId, barcode],
      limit: 1,
    );
    
    if (localMaps.isNotEmpty) {
      final map = Map<String, dynamic>.from(localMaps.first);
      map['is_service'] = map['is_service'] == 1;
      
      final metadataStr = map['metadata'] as String? ?? '{}';
      final metadataMap = jsonDecode(metadataStr) as Map<String, dynamic>;
      map['metadata'] = metadataMap;
      
      map['barcode'] = map['barcode'] ?? metadataMap['barcode'];
      
      return Product.fromJson(map);
    }
    
    // 2. Fallback to direct cloud database scan (high performance via idx_products_barcode)
    if (_connectivity.isOnline) {
      try {
        final cloudMatch = await supabase
            .from('products')
            .select('id, shop_id, name, price, stock_quantity, category, description, is_service, gst_rate, hsn_sac_code, barcode, cost_price, metadata, unit')
            .eq('shop_id', shopId)
            .eq('barcode', barcode)
            .maybeSingle();
            
        if (cloudMatch != null) {
          final mapped = Map<String, dynamic>.from(cloudMatch);
          mapped['is_service'] = (mapped['is_service'] == true) ? 1 : 0;
          
          final metadataMap = Map<String, dynamic>.from(mapped['metadata'] ?? {});
          if (mapped['barcode'] != null) {
            metadataMap['barcode'] = mapped['barcode'];
          }
          mapped['metadata'] = jsonEncode(metadataMap);
          
          // Cache the found product locally
          final sqliteMapped = Map<String, dynamic>.from(mapped);
          await _localDb.insert('products', sqliteMapped);
          
          return Product.fromJson(mapped);
        }
      } catch (e) {
        debugPrint('[ProductRepository] Barcode cloud lookup failed: $e');
      }
    }
    return null;
  }

  /// Retrieves a specific product by its ID
  Future<Product?> getProductById(String id) async {
    final localMaps = await _localDb.queryAll(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    
    if (localMaps.isNotEmpty) {
      final map = Map<String, dynamic>.from(localMaps.first);
      map['is_service'] = map['is_service'] == 1;
      
      final metadataStr = map['metadata'] as String? ?? '{}';
      final metadataMap = jsonDecode(metadataStr) as Map<String, dynamic>;
      map['metadata'] = metadataMap;
      
      if (metadataMap.containsKey('barcode')) {
        map['barcode'] = metadataMap['barcode'];
      }
      
      return Product.fromJson(map);
    }
    
    if (_connectivity.isOnline) {
      try {
        final cloudMatch = await supabase
            .from('products')
            .select('id, shop_id, name, price, stock_quantity, category, description, is_service, gst_rate, hsn_sac_code, barcode, cost_price, metadata, unit')
            .eq('id', id)
            .maybeSingle();
            
        if (cloudMatch != null) {
          final mapped = Map<String, dynamic>.from(cloudMatch);
          mapped['is_service'] = (mapped['is_service'] == true) ? 1 : 0;
          
          final metadataMap = Map<String, dynamic>.from(mapped['metadata'] ?? {});
          if (mapped['barcode'] != null) {
            metadataMap['barcode'] = mapped['barcode'];
          }
          mapped['metadata'] = jsonEncode(metadataMap);
          
          final sqliteMapped = Map<String, dynamic>.from(mapped);
          await _localDb.insert('products', sqliteMapped);
          
          return Product.fromJson(mapped);
        }
      } catch (e) {
        debugPrint('[ProductRepository] Product ID cloud lookup failed: $e');
      }
    }
    return null;
  }

  /// Instantly saves product locally and queues background sync.
  /// On web, writes directly to Supabase to avoid AI stale-data issues.
  Future<void> saveProduct(Product product) async {
    final map = product.toJson();
    map['is_service'] = product.isService ? 1 : 0;

    // Inject barcode from high level field into metadata map for SQLite storage
    final metadataMap = Map<String, dynamic>.from(map['metadata'] ?? {});
    if (product.barcode != null) {
      metadataMap['barcode'] = product.barcode;
    }
    map['metadata'] = jsonEncode(metadataMap);

    // Web fast-path: skip local queue, write directly to Supabase
    if (kIsWeb) {
      await supabase.from('products').upsert(product.toJson());
      await _localDb.insert('products', map);
      return;
    }

    // 1. Write locally
    await _localDb.insert('products', map);

    // 2. Queue for background sync
    await _syncManager.queueOperation(
      tableName: 'products',
      action: 'INSERT',
      recordId: product.id,
      payload: product.toJson(),
    );
  }

  /// Instantly updates product locally and queues background sync.
  /// On web, writes directly to Supabase to avoid AI stale-data issues.
  Future<void> updateProduct(Product product) async {
    final map = product.toJson();
    map['is_service'] = product.isService ? 1 : 0;

    // Inject barcode from high level field into metadata map for SQLite storage
    final metadataMap = Map<String, dynamic>.from(map['metadata'] ?? {});
    if (product.barcode != null) {
      metadataMap['barcode'] = product.barcode;
    }
    map['metadata'] = jsonEncode(metadataMap);

    // Web fast-path: skip local queue, write directly to Supabase
    if (kIsWeb) {
      await supabase.from('products').upsert(product.toJson());
      await _localDb.update(
        'products',
        map,
        where: 'id = ?',
        whereArgs: [product.id],
      );
      return;
    }

    // 1. Write locally
    await _localDb.update(
      'products',
      map,
      where: 'id = ?',
      whereArgs: [product.id],
    );

    // 2. Queue for background sync
    await _syncManager.queueOperation(
      tableName: 'products',
      action: 'UPDATE',
      recordId: product.id,
      payload: product.toJson(),
    );
  }

  /// Instantly deletes product locally and queues background sync.
  /// On web, deletes directly from Supabase to avoid AI stale-data issues.
  Future<void> deleteProduct(String id) async {
    // Web fast-path: skip local queue, delete directly from Supabase
    if (kIsWeb) {
      await supabase.from('products').delete().eq('id', id);
      await _localDb.delete(
        'products',
        where: 'id = ?',
        whereArgs: [id],
      );
      return;
    }

    // 1. Delete locally
    await _localDb.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );

    // 2. Queue for background sync
    await _syncManager.queueOperation(
      tableName: 'products',
      action: 'DELETE',
      recordId: id,
      payload: {},
    );
  }

  /// Relatively adjusts a product's stock levels locally and queues it for background sync.
  /// On web, calls the Supabase RPC directly to avoid AI stale-data issues.
  Future<void> adjustStock(String id, int delta) async {
    // Web fast-path: call Supabase RPC directly
    if (kIsWeb) {
      await supabase.rpc('adjust_product_stock', params: {
        'p_id': id,
        'p_delta': delta,
      });
      return;
    }

    // 1. Update SQLite locally first
    await _localDb.rawUpdate(
      'UPDATE products SET stock_quantity = stock_quantity + ? WHERE id = ?',
      [delta, id],
    );

    // 2. Queue for background sync
    await _syncManager.queueOperation(
      tableName: 'products',
      action: 'ADJUST_STOCK',
      recordId: id,
      payload: {'id': id, 'delta': delta},
    );
  }
}
