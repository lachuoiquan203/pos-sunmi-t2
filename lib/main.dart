import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:sunmi_printer_plus/enums.dart';
import 'package:sunmi_printer_plus/sunmi_style.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const OchaLocalPosApp());
}

class OchaLocalPosApp extends StatelessWidget {
  const OchaLocalPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lá Chuối POS Local',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFD84315),
        scaffoldBackgroundColor: const Color(0xFFF4F5F7),
        useMaterial3: false,
      ),
      home: const PosMainScreen(),
    );
  }
}

class LocalDatabase {
  static Database? _db;

  static Future get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'ocha_local_sunmi.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT,
            name TEXT,
            price INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            table_name TEXT,
            items_json TEXT,
            total INTEGER,
            payment_method TEXT,
            status TEXT,
            created_at TEXT,
            synced INTEGER DEFAULT 0
          )
        ''');

        final initialMenu = [
          {'category': 'Bánh Cuốn Nóng', 'name': 'Bánh cuốn đặc biệt', 'price': 45000},
          {'category': 'Bánh Cuốn Nóng', 'name': 'Bánh cuốn thịt chả', 'price': 35000},
          {'category': 'Bánh Cuốn Nóng', 'name': 'Bánh cuốn trứng', 'price': 40000},
          {'category': 'Bánh Cuốn Nóng', 'name': 'Chả lụa thêm (Đĩa)', 'price': 15000},
          {'category': 'Bánh Dân Gian', 'name': 'Bánh ít lá gai', 'price': 10000},
          {'category': 'Bánh Dân Gian', 'name': 'Bánh bò thốt nốt', 'price': 25000},
          {'category': 'Bánh Dân Gian', 'name': 'Bánh da lợn', 'price': 20000},
          {'category': 'Bánh Dân Gian', 'name': 'Bánh khoai mì nướng', 'price': 25000},
          {'category': 'Bánh Dân Gian', 'name': 'Khoai mỳ chuối hấp', 'price': 20000},
          {'category': 'Bánh Dân Gian', 'name': 'Bánh tét', 'price': 65000},
          {'category': 'Đồ Uống & Chè', 'name': 'Chè đậu trắng', 'price': 20000},
          {'category': 'Đồ Uống & Chè', 'name': 'Nước đinh lăng thảo mộc', 'price': 15000},
          {'category': 'Đồ Uống & Chè', 'name': 'Sương sâm / Rong biển', 'price': 15000},
        ];

        for (var item in initialMenu) {
          await db.insert('products', item);
        }
      },
    );
  }
}

class SunmiPrinterHelper {
  static bool isConnected = false;

  static Future initPrinter() async {
    try {
      bool? bound = await SunmiPrinter.bindingPrinter();
      isConnected = bound ?? false;
    } catch (e) {
      isConnected = false;
    }
  }

  static Future printReceipt({
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String tableName,
    required dynamic items,
    required int total,
    required String paymentMethod,
    required bool isKitchenTicket,
    required bool openCashDrawer,
  }) async {
    if (!isConnected) await initPrinter();
    final currency = NumberFormat("#,###", "vi_VN");
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    try {
      await SunmiPrinter.initPrinter();
      await SunmiPrinter.startTransactionPrint(true);

      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      if (isKitchenTicket) {
        await SunmiPrinter.printText('PHIẾU BẾP / TẠM TÍNH',
            style: SunmiStyle(fontSize: SunmiFontSize.XL, bold: true));
      } else {
        await SunmiPrinter.printText(storeName,
            style: SunmiStyle(fontSize: SunmiFontSize.XL, bold: true));
        await SunmiPrinter.printText(storeAddress,
            style: SunmiStyle(fontSize: SunmiFontSize.MD));
        await SunmiPrinter.printText('ĐT: $storePhone',
            style: SunmiStyle(fontSize: SunmiFontSize.MD));
        await SunmiPrinter.lineWrap(1);
        await SunmiPrinter.printText('HÓA ĐƠN THANH TOÁN',
            style: SunmiStyle(fontSize: SunmiFontSize.LG, bold: true));
      }

      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
      await SunmiPrinter.printText('Bàn/Đơn: $tableName');
      await SunmiPrinter.printText('Thời gian: $now');
      await SunmiPrinter.printText('------------------------------------------------');

      for (var item in items) {
        String name = item['name'].toString();
        int qty = item['qty'] as int;
        int price = item['price'] as int;
        int subTotal = qty * price;
        String note = (item['note'] ?? '').toString();

        await SunmiPrinter.printText(name, style: SunmiStyle(bold: true));
        if (note.isNotEmpty) {
          await SunmiPrinter.printText('  (*Ghi chú: $note)');
        }
        if (!isKitchenTicket) {
          String leftCol = '  $qty x${currency.format(price)}';
          String rightCol = '${currency.format(subTotal)} đ';
          int spaces = 48 - leftCol.length - rightCol.length;
          String line = leftCol + (' ' * (spaces.isNegative ? 1 : spaces + 1)) + rightCol;
          await SunmiPrinter.printText(line);
        } else {
          await SunmiPrinter.printText('  Số lượng: x$qty',
              style: SunmiStyle(fontSize: SunmiFontSize.LG, bold: true));
        }
      }

      await SunmiPrinter.printText('------------------------------------------------');

      if (!isKitchenTicket) {
        await SunmiPrinter.setAlignment(SunmiPrintAlign.RIGHT);
        await SunmiPrinter.printText('TỔNG CỘNG: ${currency.format(total)} đ',
            style: SunmiStyle(fontSize: SunmiFontSize.LG, bold: true));
        await SunmiPrinter.printText('Thanh toán: $paymentMethod');
        await SunmiPrinter.lineWrap(1);
        await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
        await SunmiPrinter.printText('Cảm ơn Quý khách & Hẹn gặp lại!');
      }

      await SunmiPrinter.lineWrap(4);
      await SunmiPrinter.cut();

      if (openCashDrawer) {
        await SunmiPrinter.openDrawer();
      }

      await SunmiPrinter.exitTransactionPrint(true);
    } catch (e) {
      debugPrint('Lỗi máy in Sunmi: $e');
    }
  }
}

class PosMainScreen extends StatefulWidget {
  const PosMainScreen({super.key});

  @override
  State createState() => _PosMainScreenState();
}

class _PosMainScreenState extends State {
  final currency = NumberFormat("#,###", "vi_VN");

  String storeName = 'LÁ CHUỐI QUÁN';
  String storeAddress = '203 Nguyễn Văn Trỗi, P.4, Vũng Tàu';
  String storePhone = '0328000203';
  String googleSheetWebhookUrl = '';

  var allProducts = [];
  var categories = ['Tất cả'];
  String selectedCategory = 'Tất cả';

  int? currentOrderId;
  String currentTableName = 'Mang về';
  var cart = [];
  var openOrders = [];

  @override
  void initState() {
    super.initState();
    SunmiPrinterHelper.initPrinter();
    _loadData();
  }

  Future _loadData() async {
    final Database db = await LocalDatabase.db;
    final prods = await db.query('products');
    final opens = await db.query('orders', where: "status = 'OPEN'", orderBy: 'id DESC');

    final cats = ['Tất cả'];
    for (var p in prods) {
      final c = p['category'].toString();
      if (!cats.contains(c)) {
        cats.add(c);
      }
    }

    setState(() {
      allProducts = prods;
      categories = cats;
      openOrders = opens;
    });
  }

  void _addToCart(dynamic product) {
    setState(() {
      int index = cart.indexWhere((item) => item['id'] == product['id'] && (item['note'] ?? '') == '');
      if (index != -1) {
        cart[index]['qty'] = (cart[index]['qty'] as int) + 1;
      } else {
        cart.add({
          'id': product['id'],
          'name': product['name'],
          'price': product['price'],
          'qty': 1,
          'note': '',
        });
      }
    });
  }

  int get cartTotal {
    int sum = 0;
    for (var item in cart) {
      sum += (item['price'] as int) * (item['qty'] as int);
    }
    return sum;
  }

  Future _saveOpenOrder({bool printKitchen = false}) async {
    if (cart.isEmpty) return;
    final Database db = await LocalDatabase.db;
    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    final data = {
      'table_name': currentTableName,
      'items_json': jsonEncode(cart),
      'total': cartTotal,
      'payment_method': 'Chưa thanh toán',
      'status': 'OPEN',
      'created_at': now,
    };

    if (currentOrderId == null) {
      await db.insert('orders', data);
    } else {
      await db.update('orders', data, where: 'id = ?', whereArgs: [currentOrderId]);
    }

    if (printKitchen) {
      await SunmiPrinterHelper.printReceipt(
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        tableName: currentTableName,
        items: cart,
        total: cartTotal,
        paymentMethod: '',
        isKitchenTicket: true,
        openCashDrawer: false,
      );
    }

    _clearCurrentOrder();
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã lưu đơn [$currentTableName] thành công!')),
      );
    }
  }

  Future _checkoutOrder(String paymentMethod) async {
    if (cart.isEmpty) return;
    final Database db = await LocalDatabase.db;
    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    final data = {
      'table_name': currentTableName,
      'items_json': jsonEncode(cart),
      'total': cartTotal,
      'payment_method': paymentMethod,
      'status': 'PAID',
      'created_at': now,
      'synced': 0,
    };

    int orderId;
    if (currentOrderId == null) {
      orderId = await db.insert('orders', data);
    } else {
      orderId = currentOrderId!;
      await db.update('orders', data, where: 'id = ?', whereArgs: [orderId]);
    }

    await SunmiPrinterHelper.printReceipt(
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      tableName: currentTableName,
      items: cart,
      total: cartTotal,
      paymentMethod: paymentMethod,
      isKitchenTicket: false,
      openCashDrawer: paymentMethod == 'Tiền mặt',
    );

    if (googleSheetWebhookUrl.isNotEmpty) {
      _syncSingleOrderToGoogleSheets(orderId, data);
    }

    _clearCurrentOrder();
    await _loadData();
  }

  Future _syncSingleOrderToGoogleSheets(int orderId, dynamic orderData) async {
    try {
      final response = await http.post(
        Uri.parse(googleSheetWebhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'order_id': orderId,
          'created_at': orderData['created_at'],
          'table_name': orderData['table_name'],
          'payment_method': orderData['payment_method'],
          'total': orderData['total'],
          'items': jsonDecode(orderData['items_json'].toString()),
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 || response.statusCode == 302) {
        final Database db = await LocalDatabase.db;
        await db.update('orders', {'synced': 1}, where: 'id = ?', whereArgs: [orderId]);
      }
    } catch (_) {}
  }

  void _clearCurrentOrder() {
    setState(() {
      currentOrderId = null;
      currentTableName = 'Mang về';
      cart = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = selectedCategory == 'Tất cả'
        ? allProducts
        : allProducts.where((p) => p['category'] == selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF263238),
        elevation: 2,
        title: Row(
          children: [
            const Icon(Icons.storefront, color: Colors.orangeAccent),
            const SizedBox(width: 8),
            Text(storeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(width: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
              icon: const Icon(Icons.table_restaurant, size: 18),
              label: Text('Đơn: $currentTableName', style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _showSelectTableDialog,
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              icon: const Icon(Icons.receipt_long, size: 18),
              label: Text('Đơn đang mở (${openOrders.length})'),
              onPressed: _showOpenOrdersModal,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('Thêm món'),
            onPressed: _showAddProductDialog,
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
            icon: const Icon(Icons.bar_chart),
            label: const Text('Báo cáo & Xuất CSV / Sheets'),
            onPressed: _showReportAndExportModal,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 65,
            child: Column(
              children: [
                Container(
                  height: 56,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final cat = categories[idx];
                      final isSelected = cat == selectedCategory;
                      return ChoiceChip(
                        label: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: const Color(0xFFD84315),
                        backgroundColor: Colors.grey.shade200,
                        onSelected: (_) => setState(() => selectedCategory = cat),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 1.45,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, idx) {
                      final item = filteredProducts[idx];
                      return InkWell(
                        onTap: () => _addToCart(item),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))
                            ],
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item['name'].toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.deepOrange.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${currency.format(item['price'])} đ',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFD84315),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            flex: 35,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Colors.grey.shade100,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          currentOrderId == null
                              ? 'HÓA ĐƠN MỚI ($currentTableName)'
                              : 'ĐƠN #$currentOrderId ($currentTableName)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (cart.isNotEmpty)
                          TextButton.icon(
                            onPressed: _clearCurrentOrder,
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                            label: const Text('Xóa giỏ', style: TextStyle(color: Colors.red)),
                          )
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: cart.isEmpty
                        ? const Center(
                            child: Text('Chạm vào món bên trái để gọi món',
                                style: TextStyle(color: Colors.grey, fontSize: 16)),
                          )
                        : ListView.separated(
                            itemCount: cart.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final item = cart[idx];
                              return ListTile(
                                title: Text(item['name'].toString(),
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: GestureDetector(
                                  onTap: () => _showNoteDialog(idx),
                                  child: Text(
                                    (item['note'] ?? '').toString().isEmpty
                                        ? '${currency.format(item['price'])} đ  •  + Ghi chú'
                                        : '${currency.format(item['price']
