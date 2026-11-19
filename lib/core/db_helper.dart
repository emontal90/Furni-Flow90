import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:furniture_erp/core/category_stock_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;
  static const int currentDbVersion = 2;

  DBHelper._init();

  Future<void> closeDatabase() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDB('furniture_erp.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    Future<void> onConfigure(Database db) async {
      try {
        await db.execute('PRAGMA foreign_keys = ON');
      } catch (_) {}
    }

    Future<void> onOpen(Database db) async {
      try {
        await CategoryStockHelper.syncDatabaseStock(db);
      } catch (_) {}
    }

    if (kIsWeb) {
      return await openDatabase(
        filePath,
        version: currentDbVersion,
        onConfigure: onConfigure,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
        onOpen: onOpen,
      );
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(
      path,
      version: currentDbVersion,
      onConfigure: onConfigure,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onOpen: onOpen,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        components_json TEXT NOT NULL,
        stock_qty INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE upholsterer_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        upholsterer_name TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        category_name TEXT NOT NULL,
        piece_name TEXT,
        total_sent INTEGER NOT NULL DEFAULT 0,
        received_qty INTEGER NOT NULL DEFAULT 0,
        sent_date TEXT NOT NULL,
        received_date TEXT,
        sets_sent INTEGER DEFAULT 1,
        sets_received INTEGER DEFAULT 0,
        pieces_json TEXT,
        unit_cost REAL NOT NULL DEFAULT 0,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        customer_name TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        category_name TEXT NOT NULL,
        selected_components_json TEXT NOT NULL,
        specs TEXT,
        delivery_date TEXT NOT NULL,
        order_type TEXT NOT NULL,
        sets_count INTEGER DEFAULT 1,
        total_price REAL NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'waiting',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS archived_orders (
        id INTEGER PRIMARY KEY,
        customer_id INTEGER NOT NULL,
        customer_name TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        category_name TEXT NOT NULL,
        selected_components_json TEXT NOT NULL,
        specs TEXT,
        delivery_date TEXT NOT NULL,
        order_type TEXT NOT NULL,
        sets_count INTEGER DEFAULT 1,
        total_price REAL NOT NULL DEFAULT 0,
        paid_amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        archived_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        category_name TEXT NOT NULL,
        movement_type TEXT NOT NULL,
        qty_change INTEGER NOT NULL,
        stock_after INTEGER NOT NULL,
        pieces_json TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS upholsterer_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER,
        upholsterer_name TEXT NOT NULL,
        category_id INTEGER NOT NULL,
        category_name TEXT NOT NULL,
        action_type TEXT NOT NULL,
        sets_count INTEGER NOT NULL DEFAULT 0,
        pieces_json TEXT NOT NULL,
        total_pieces INTEGER NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        action_date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await _createIndexes(db);
  }

  /// ترقية آمنة ومنظمة لقاعدة البيانات عند الانتقال من إصدار قديم دون تكرار DDL عند كل فتح
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    Future<void> safeExec(String sql) async {
      try {
        await db.execute(sql);
      } catch (_) {}
    }

    if (oldVersion < 2) {
      // ضمان وجود الجداول والأعمدة التاريخية للمستخدمين الذين يرقّون من إصدار 1.0.x
      await safeExec('ALTER TABLE upholsterer_batches ADD COLUMN pieces_json TEXT');
      await safeExec('ALTER TABLE upholsterer_batches ADD COLUMN received_date TEXT');
      await safeExec('ALTER TABLE upholsterer_batches ADD COLUMN sets_sent INTEGER DEFAULT 1');
      await safeExec('ALTER TABLE upholsterer_batches ADD COLUMN sets_received INTEGER DEFAULT 0');
      await safeExec('ALTER TABLE upholsterer_batches ADD COLUMN unit_cost REAL NOT NULL DEFAULT 0');

      await safeExec('ALTER TABLE orders ADD COLUMN sets_count INTEGER DEFAULT 1');
      await safeExec('ALTER TABLE orders ADD COLUMN total_price REAL NOT NULL DEFAULT 0');
      await safeExec('ALTER TABLE orders ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0');

      await safeExec('''
        CREATE TABLE IF NOT EXISTS archived_orders (
          id INTEGER PRIMARY KEY,
          customer_id INTEGER NOT NULL,
          customer_name TEXT NOT NULL,
          category_id INTEGER NOT NULL,
          category_name TEXT NOT NULL,
          selected_components_json TEXT NOT NULL,
          specs TEXT,
          delivery_date TEXT NOT NULL,
          order_type TEXT NOT NULL,
          sets_count INTEGER DEFAULT 1,
          total_price REAL NOT NULL DEFAULT 0,
          paid_amount REAL NOT NULL DEFAULT 0,
          status TEXT NOT NULL,
          created_at TEXT NOT NULL,
          archived_at TEXT NOT NULL
        )
      ''');
      await safeExec('ALTER TABLE archived_orders ADD COLUMN sets_count INTEGER DEFAULT 1');
      await safeExec('ALTER TABLE archived_orders ADD COLUMN total_price REAL NOT NULL DEFAULT 0');
      await safeExec('ALTER TABLE archived_orders ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0');

      await safeExec('''
        CREATE TABLE IF NOT EXISTS stock_movements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category_id INTEGER NOT NULL,
          category_name TEXT NOT NULL,
          movement_type TEXT NOT NULL,
          qty_change INTEGER NOT NULL,
          stock_after INTEGER NOT NULL,
          pieces_json TEXT,
          notes TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      await safeExec('ALTER TABLE stock_movements ADD COLUMN pieces_json TEXT');

      await safeExec('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

      await safeExec('''
        CREATE TABLE IF NOT EXISTS upholsterer_transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          batch_id INTEGER,
          upholsterer_name TEXT NOT NULL,
          category_id INTEGER NOT NULL,
          category_name TEXT NOT NULL,
          action_type TEXT NOT NULL,
          sets_count INTEGER NOT NULL DEFAULT 0,
          pieces_json TEXT NOT NULL,
          total_pieces INTEGER NOT NULL DEFAULT 0,
          unit_cost REAL NOT NULL DEFAULT 0,
          action_date TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await safeExec('ALTER TABLE upholsterer_transactions ADD COLUMN unit_cost REAL NOT NULL DEFAULT 0');

      await _createIndexes(db);
    }
  }

  Future<void> _createIndexes(Database db) async {
    const indexes = [
      'CREATE INDEX IF NOT EXISTS idx_orders_status_date ON orders(status, delivery_date)',
      'CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_orders_category_id ON orders(category_id)',
      'CREATE INDEX IF NOT EXISTS idx_stock_movements_cat_date ON stock_movements(category_id, created_at)',
      'CREATE INDEX IF NOT EXISTS idx_uph_batches_cat ON upholsterer_batches(category_id)',
      'CREATE INDEX IF NOT EXISTS idx_uph_tx_batch_date ON upholsterer_transactions(batch_id, action_date)',
      'CREATE INDEX IF NOT EXISTS idx_archived_orders_cat ON archived_orders(category_id)',
    ];
    for (final sql in indexes) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
  }
}
