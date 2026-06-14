import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  // In-memory database fallback for Flutter Web
  final Map<String, List<Map<String, dynamic>>> _webDb = {
    'products': [],
    'customers': [],
    'sales': [],
    'sync_queue': [],
    'chat_messages': [],
  };
  int _webSyncQueueIdCounter = 1;
  bool _isWebDbLoaded = false;

  LocalDatabase._init();

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('Direct SQLite database access is not supported on Web.');
    }
    if (_database != null) return _database!;
    _database = await _initDB('dukan_sathi.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Products Table
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        stock_quantity INTEGER NOT NULL DEFAULT 0,
        category TEXT NOT NULL,
        description TEXT,
        is_service INTEGER NOT NULL DEFAULT 0,
        gst_rate REAL NOT NULL DEFAULT 0.0,
        hsn_sac_code TEXT,
        barcode TEXT,
        cost_price REAL NOT NULL DEFAULT 0.0,
        metadata TEXT NOT NULL DEFAULT '{}',
        unit TEXT DEFAULT 'pcs'
      )
    ''');

    // 2. Customers Table
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        current_balance REAL NOT NULL DEFAULT 0.0
      )
    ''');

    // 3. Sales Table (Full compliance schema matching Postgres sales table)
    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        invoice_number TEXT,
        shop_id TEXT NOT NULL,
        invoice_id TEXT NOT NULL,
        customer_id TEXT,
        customer_name TEXT,
        customer_state TEXT,
        amount REAL NOT NULL,
        amount_paid REAL NOT NULL DEFAULT 0.0,
        due_amount REAL NOT NULL DEFAULT 0.0,
        payment_status TEXT NOT NULL,
        discount_type TEXT,
        discount_value REAL,
        discount_amount REAL NOT NULL DEFAULT 0.0,
        subtotal_before_discount REAL,
        subtotal_after_discount REAL,
        timestamp TEXT NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'pending',
        status TEXT NOT NULL DEFAULT 'approved',
        updated_at TEXT
      )
    ''');

    // 4. Sync Queue Table for offline updates background synchronization
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        action TEXT NOT NULL,
        record_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 5. Chat Messages Table for offline persistent history
    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        shop_id TEXT NOT NULL,
        text TEXT NOT NULL,
        type TEXT NOT NULL,
        payload TEXT,
        is_typing INTEGER NOT NULL DEFAULT 0,
        timestamp TEXT NOT NULL
      )
    ''');

    // 6. Create indexes for fast querying on shop_id, stock, and timestamp
    await db.execute('CREATE INDEX idx_products_shop_id ON products(shop_id)');
    await db.execute('CREATE INDEX idx_products_stock ON products(shop_id, stock_quantity)');
    await db.execute('CREATE INDEX idx_customers_shop_id ON customers(shop_id)');
    await db.execute('CREATE INDEX idx_sales_shop_id ON sales(shop_id)');
    await db.execute('CREATE INDEX idx_sales_timestamp ON sales(shop_id, timestamp DESC)');
    await db.execute('CREATE INDEX idx_chat_messages_shop_id ON chat_messages(shop_id)');
    await db.execute('CREATE INDEX idx_products_barcode ON products(shop_id, barcode)');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_shop_id ON products(shop_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_products_stock ON products(shop_id, stock_quantity)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_shop_id ON customers(shop_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_shop_id ON sales(shop_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_timestamp ON sales(shop_id, timestamp DESC)');
      
      try {
        await db.execute('ALTER TABLE sync_queue ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }

    if (oldVersion < 3) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS chat_messages (
            id TEXT PRIMARY KEY,
            shop_id TEXT NOT NULL,
            text TEXT NOT NULL,
            type TEXT NOT NULL,
            payload TEXT,
            is_typing INTEGER NOT NULL DEFAULT 0,
            timestamp TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_chat_messages_shop_id ON chat_messages(shop_id)');
      } catch (_) {}
    }

    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN barcode TEXT');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(shop_id, barcode)');
      } catch (_) {}
    }

    if (oldVersion < 5) {
      try {
        await db.execute("ALTER TABLE products ADD COLUMN cost_price REAL DEFAULT 0.0");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE products ADD COLUMN unit TEXT DEFAULT 'pcs'");
      } catch (_) {}
    }
  }

  Future<void> _ensureWebDbLoaded() async {
    if (!kIsWeb || _isWebDbLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('dukan_sathi_web_db');
      if (jsonStr != null) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          if (value is List) {
            _webDb[key] = List<Map<String, dynamic>>.from(
              value.map((item) => Map<String, dynamic>.from(item as Map)),
            );
          }
        });
        
        // Restore sync queue ID counter to prevent key collisions
        final syncQueue = _webDb['sync_queue'] ?? [];
        if (syncQueue.isNotEmpty) {
          final maxId = syncQueue.map((item) => item['id'] as int? ?? 0).reduce((a, b) => a > b ? a : b);
          _webSyncQueueIdCounter = maxId + 1;
        }
      }
    } catch (e) {
      debugPrint('[LocalDatabase] Failed to load web db: $e');
    }
    _isWebDbLoaded = true;
  }

  Future<void> _saveWebDb() async {
    if (!kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dukan_sathi_web_db', jsonEncode(_webDb));
    } catch (e) {
      debugPrint('[LocalDatabase] Failed to save web db: $e');
    }
  }

  // Helper CRUD methods
  Future<int> insert(String table, Map<String, dynamic> row) async {
    if (kIsWeb) {
      await _ensureWebDbLoaded();
      final list = _webDb[table] ??= [];
      final rowCopy = Map<String, dynamic>.from(row);
      
      // Handle auto-increment for sync_queue ID on web
      if (table == 'sync_queue' && !rowCopy.containsKey('id')) {
        rowCopy['id'] = _webSyncQueueIdCounter++;
      }
      
      // If table has primary key, replace any existing item with the same primary key
      String? primaryKeyField;
      if (table == 'products' || table == 'customers' || table == 'sales' || table == 'chat_messages') {
        primaryKeyField = 'id';
      } else if (table == 'sync_queue') {
        primaryKeyField = 'id';
      }
      
      if (primaryKeyField != null && rowCopy[primaryKeyField] != null) {
        list.removeWhere((item) => item[primaryKeyField] == rowCopy[primaryKeyField]);
      }
      
      list.add(rowCopy);
      await _saveWebDb();
      return rowCopy['id'] is int ? rowCopy['id'] as int : 1;
    }

    final db = await database;
    return await db.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  bool _rowMatches(Map<String, dynamic> row, String where, List<dynamic> whereArgs) {
    if (where.trim().isEmpty) return true;
    
    // Standardize spacing
    final normalized = where.replaceAll(RegExp(r'\s+'), ' ').trim();
    final parts = normalized.split(RegExp(r'\s+AND\s+', caseSensitive: false));
    int argIndex = 0;
    
    for (final part in parts) {
      final normalizedPart = part.trim();
      final normalizedPartLower = normalizedPart.toLowerCase();
      
      // Match "column = ?"
      if (normalizedPartLower.endsWith(' = ?')) {
        final column = normalizedPart.substring(0, normalizedPart.indexOf(' ')).trim().toLowerCase();
        if (argIndex >= whereArgs.length) return false;
        final val = whereArgs[argIndex++];
        final rowVal = row[column];
        if (rowVal?.toString() != val?.toString()) {
          return false;
        }
      }
      // Match "column = 'value'" or "column = "value""
      else if (normalizedPartLower.contains(' = ')) {
        final eqIndex = normalizedPart.indexOf('=');
        final column = normalizedPart.substring(0, eqIndex).trim().toLowerCase();
        var valStr = normalizedPart.substring(eqIndex + 1).trim();
        if ((valStr.startsWith("'") && valStr.endsWith("'")) || (valStr.startsWith('"') && valStr.endsWith('"'))) {
          valStr = valStr.substring(1, valStr.length - 1);
        }
        final rowVal = row[column];
        if (rowVal?.toString() != valStr) {
          return false;
        }
      }
      // Match "column < ?"
      else if (normalizedPartLower.endsWith(' < ?')) {
        final column = normalizedPart.substring(0, normalizedPart.indexOf(' ')).trim().toLowerCase();
        if (argIndex >= whereArgs.length) return false;
        final val = whereArgs[argIndex++];
        final rowVal = row[column];
        if (rowVal == null || val == null) return false;
        final rowNum = num.tryParse(rowVal.toString()) ?? 0;
        final valNum = num.tryParse(val.toString()) ?? 0;
        if (rowNum >= valNum) {
          return false;
        }
      }
      // Match "column >= ?"
      else if (normalizedPartLower.endsWith(' >= ?')) {
        final column = normalizedPart.substring(0, normalizedPart.indexOf(' ')).trim().toLowerCase();
        if (argIndex >= whereArgs.length) return false;
        final val = whereArgs[argIndex++];
        final rowVal = row[column];
        if (rowVal == null || val == null) return false;
        if (rowVal.toString().compareTo(val.toString()) < 0) {
          return false;
        }
      }
      // Match "column LIKE ?"
      else if (normalizedPartLower.endsWith(' like ?')) {
        final column = normalizedPart.substring(0, normalizedPart.indexOf(' ')).trim().toLowerCase();
        if (argIndex >= whereArgs.length) return false;
        final val = whereArgs[argIndex++].toString().replaceAll('%', '').replaceAll('"', '').toLowerCase();
        final rowVal = row[column];
        final rowValStr = rowVal is String ? rowVal : jsonEncode(rowVal ?? {});
        if (!rowValStr.toLowerCase().contains(val)) {
          return false;
        }
      }
      // Match "column NOT IN (?, ?, ...)"
      else if (normalizedPartLower.contains(' not in (')) {
        final colIndex = normalizedPartLower.indexOf(' not in');
        final column = normalizedPart.substring(0, colIndex).trim().toLowerCase();
        final placeholderCount = '?'.allMatches(normalizedPart).length;
        if (argIndex + placeholderCount > whereArgs.length) return false;
        final excludedVals = whereArgs.sublist(argIndex, argIndex + placeholderCount).map((e) => e.toString()).toSet();
        argIndex += placeholderCount;
        
        final rowVal = row[column];
        if (excludedVals.contains(rowVal?.toString())) {
          return false;
        }
      }
    }
    
    return true;
  }

  Future<List<Map<String, dynamic>>> queryAll(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (kIsWeb) {
      await _ensureWebDbLoaded();
      var list = List<Map<String, dynamic>>.from(_webDb[table] ?? []);
      
      // Simple where clause filtering
      if (where != null && whereArgs != null) {
        list = list.where((item) => _rowMatches(item, where, whereArgs)).toList();
      }
      
      // Simple orderBy
      if (orderBy != null) {
        if (orderBy.contains('timestamp DESC')) {
          list.sort((a, b) {
            final tA = a['timestamp']?.toString() ?? '';
            final tB = b['timestamp']?.toString() ?? '';
            return tB.compareTo(tA);
          });
        } else if (orderBy.contains('timestamp ASC')) {
          list.sort((a, b) {
            final tA = a['timestamp']?.toString() ?? '';
            final tB = b['timestamp']?.toString() ?? '';
            return tA.compareTo(tB);
          });
        } else if (orderBy.contains('name ASC')) {
          list.sort((a, b) {
            final nA = a['name']?.toString() ?? '';
            final nB = b['name']?.toString() ?? '';
            return nA.compareTo(nB);
          });
        } else if (orderBy.contains('id ASC')) {
          list.sort((a, b) {
            final idA = a['id'] is int ? a['id'] as int : 0;
            final idB = b['id'] is int ? b['id'] as int : 0;
            return idA.compareTo(idB);
          });
        }
      }
      
      // Offset and Limit
      int start = offset ?? 0;
      if (start > list.length) return [];
      var result = list.sublist(start);
      if (limit != null && limit < result.length) {
        result = result.sublist(0, limit);
      }
      return result;
    }

    final db = await database;
    return await db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> update(
    String table,
    Map<String, dynamic> row, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    if (kIsWeb) {
      await _ensureWebDbLoaded();
      final list = _webDb[table] ?? [];
      int count = 0;
      for (var i = 0; i < list.length; i++) {
        if (_rowMatches(list[i], where, whereArgs)) {
          final updated = Map<String, dynamic>.from(list[i])..addAll(row);
          list[i] = updated;
          count++;
        }
      }
      await _saveWebDb();
      return count;
    }

    final db = await database;
    return await db.update(
      table,
      row,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> delete(
    String table, {
    required String where,
    required List<dynamic> whereArgs,
  }) async {
    if (kIsWeb) {
      await _ensureWebDbLoaded();
      final list = _webDb[table] ?? [];
      final before = list.length;
      list.removeWhere((item) => _rowMatches(item, where, whereArgs));
      await _saveWebDb();
      return before - list.length;
    }

    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> clearTable(String table) async {
    if (kIsWeb) {
      await _ensureWebDbLoaded();
      _webDb[table]?.clear();
      await _saveWebDb();
      return;
    }
    final db = await database;
    await db.delete(table);
  }

  /// Clears ALL local data from every table (products, customers, sales, sync_queue, chat_messages).
  /// Used for data resets or when switching accounts.
  Future<void> clearAllData() async {
    if (kIsWeb) {
      await _ensureWebDbLoaded();
      for (final key in _webDb.keys) {
        _webDb[key]?.clear();
      }
      _webSyncQueueIdCounter = 1;
      await _saveWebDb();
      debugPrint('[LocalDatabase] Web: all local data cleared.');
      return;
    }
    final db = await database;
    for (final table in ['sync_queue', 'chat_messages', 'sales', 'customers', 'products']) {
      await db.delete(table);
    }
    debugPrint('[LocalDatabase] All local data cleared.');
  }

  Future<void> executeInTransaction(Future<void> Function(Transaction txn) action) async {
    if (kIsWeb) {
      await _ensureWebDbLoaded();
      final mockTxn = MockTransaction(this);
      await action(mockTxn);
      await _saveWebDb();
      return;
    }
    final db = await database;
    await db.transaction((txn) async {
      await action(txn);
    });
  }

  Future<int> count(String table, {String? where, List<dynamic>? whereArgs}) async {
    if (kIsWeb) {
      await _ensureWebDbLoaded();
      final list = _webDb[table] ?? [];
      if (where != null && whereArgs != null) {
        return list.where((item) => _rowMatches(item, where, whereArgs)).length;
      }
      return list.length;
    }
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM $table${where != null ? ' WHERE $where' : ''}', whereArgs);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (kIsWeb) {
      return;
    }
    final db = await database;
    await db.execute(sql, arguments);
  }

  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    if (kIsWeb) {
      await _ensureWebDbLoaded();
      if (sql.contains('UPDATE products SET stock_quantity = stock_quantity + ? WHERE id = ?') && arguments != null && arguments.length >= 2) {
        final delta = arguments[0] as int;
        final id = arguments[1] as String;
        final list = _webDb['products'] ?? [];
        for (var i = 0; i < list.length; i++) {
          if (list[i]['id'] == id) {
            final updated = Map<String, dynamic>.from(list[i]);
            updated['stock_quantity'] = (updated['stock_quantity'] ?? 0) + delta;
            list[i] = updated;
            await _saveWebDb();
            return 1;
          }
        }
      }
      return 0;
    }
    final db = await database;
    return await db.rawUpdate(sql, arguments);
  }
}

// Mock Transaction class for Flutter Web compliance
class MockTransaction implements Transaction {
  final LocalDatabase _localDb;
  MockTransaction(this._localDb);

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) {
    return _localDb.insert(table, values);
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    return _localDb.delete(table, where: where ?? '', whereArgs: whereArgs ?? []);
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) {
    return _localDb.update(table, values, where: where ?? '', whereArgs: whereArgs ?? []);
  }

  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? limit, int? offset}) {
    return _localDb.queryAll(table, where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit, offset: offset);
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    return _localDb.execute(sql, arguments);
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    throw UnimplementedError();
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) {
    throw UnimplementedError();
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) {
    return _localDb.rawUpdate(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) {
    throw UnimplementedError();
  }

  @override
  Future<QueryCursor> queryCursor(String table, {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs, String? groupBy, String? having, String? orderBy, int? bufferSize, int? limit, int? offset}) {
    throw UnimplementedError('queryCursor is not supported on Web.');
  }

  @override
  Future<QueryCursor> rawQueryCursor(String sql, List<Object?>? arguments, {int? bufferSize}) {
    throw UnimplementedError('rawQueryCursor is not supported on Web.');
  }

  @override
  Batch batch() {
    throw UnimplementedError();
  }

  @override
  Database get database => throw UnimplementedError();
}
