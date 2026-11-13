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

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
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

  static Future<void> initPrinter() async {
    try {
      bool? bound = await SunmiPrinter.bindingPrinter();
      isConnected = bound ?? false;
    } catch (e) {
      isConnected = false;
    }
  }

  static Future<void> printReceipt({
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String tableName,
    required List items,
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
          String leftCol = '  $qty x ${currency.format(price)}';
          String rightCol = '${currency.format(subTotal)} đ';
          int spaces = 48 - leftCol.length - rightCol.length;
          String line = leftCol + (' ' * (spaces > 0 ? spaces : 1)) + rightCol;
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
  State<PosMainScreen> createState() => _PosMainScreenState();
}

class _PosMainScreenState extends State<PosMainScreen> {
  final currency = NumberFormat("#,###", "vi_VN");

  String storeName = 'LÁ CHUỐI QUÁN';
  String storeAddress = '203 Nguyễn Văn Trỗi, P.4, Vũng Tàu';
  String storePhone = '0328000203';
  String googleSheetWebhookUrl = '';

  List> allProducts = [];
  List<String> categories = ['Tất cả'];
  String selectedCategory = 'Tất cả';

  int? currentOrderId;
  String currentTableName = 'Mang về';
  List> cart = [];
  List> openOrders = [];

  @override
  void initState() {
    super.initState();
    SunmiPrinterHelper.initPrinter();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = await LocalDatabase.db;
    final prods = await db.query('products');
    final opens = await db.query('orders', where: "status = 'OPEN'", orderBy: 'id DESC');

    final cats = <String>{'Tất cả'};
    for (var p in prods) {
      cats.add(p['category'].toString());
    }

    setState(() {
      allProducts = prods;
      categories = cats.toList();
      openOrders = opens;
    });
  }

  void _addToCart(Map<String, dynamic> product) {
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

  int get cartTotal => cart.fold(0, (sum, item) => sum + (item['price'] as int) * (item['qty'] as int));

  Future<void> _saveOpenOrder({bool printKitchen = false}) async {
    if (cart.isEmpty) return;
    final db = await LocalDatabase.db;
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

  Future<void> _checkoutOrder(String paymentMethod) async {
    if (cart.isEmpty) return;
    final db = await LocalDatabase.db;
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

  Future<void> _syncSingleOrderToGoogleSheets(int orderId, Map<String, dynamic> orderData) async {
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
        final db = await LocalDatabase.db;
        await db.update('orders', {'synced': 1}, where: 'id = ?', whereArgs: [orderId]);
      }
    } catch (_) {}
  }

  void _clearCurrentOrder() {
    setState(() {
      currentOrderId = null;
      currentTableName = 'Mang về';
      cart.clear();
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
                                        : '${currency.format(item['price'])} đ  •  Ghi chú: ${item['note']}',
                                    style: TextStyle(
                                      color: (item['note'] ?? '').toString().isEmpty
                                          ? Colors.blueGrey
                                          : Colors.deepOrange,
                                    ),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                      onPressed: () {
                                        setState(() {
                                          int q = item['qty'] as int;
                                          if (q > 1) {
                                            item['qty'] = q - 1;
                                          } else {
                                            cart.removeAt(idx);
                                          }
                                        });
                                      },
                                    ),
                                    Text('${item['qty']}',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                      onPressed: () => setState(() => item['qty'] = (item['qty'] as int) + 1),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(top: BorderSide(color: Colors.grey.shade300)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TỔNG CỘNG:',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text(
                              '${currency.format(cartTotal)} đ',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD84315),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  side: const BorderSide(color: Colors.blueGrey),
                                ),
                                icon: const Icon(Icons.bookmark_add_outlined),
                                label: const Text('LƯU ĐƠN', style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () => _saveOpenOrder(printKitchen: false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  side: const BorderSide(color: Colors.orange),
                                  foregroundColor: Colors.deepOrange,
                                ),
                                icon: const Icon(Icons.print_outlined),
                                label: const Text('LƯU & IN BẾP',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                                onPressed: () => _saveOpenOrder(printKitchen: true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2E7D32),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                icon: const Icon(Icons.payments_outlined),
                                label: const Text('TIỀN MẶT (IN BILL)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                onPressed: () => _checkoutOrder('Tiền mặt'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1565C0),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                icon: const Icon(Icons.qr_code_2),
                                label: const Text('CHUYỂN KHOẢN',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                onPressed: () => _checkoutOrder('Chuyển khoản'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSelectTableDialog() {
    final tables = [
      'Mang về', 'ShopeeFood', 'GrabFood',
      'Bàn 1', 'Bàn 2', 'Bàn 3', 'Bàn 4', 'Bàn 5',
      'Bàn 6', 'Bàn 7', 'Bàn 8', 'Bàn 9', 'Bàn 10'
    ];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chọn Bàn / Kênh bán'),
        content: SizedBox(
          width: 500,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: tables.map((t) {
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: currentTableName == t ? Colors.deepOrange : Colors.blueGrey,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                onPressed: () {
                  setState(() => currentTableName = t);
                  Navigator.pop(context);
                },
                child: Text(t, style: const TextStyle(fontSize: 16)),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showNoteDialog(int cartIndex) {
    final ctrl = TextEditingController(text: (cart[cartIndex]['note'] ?? '').toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ghi chú món: ${cart[cartIndex]['name']}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'VD: Ít hành, không chả, mang về riêng...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () {
              setState(() => cart[cartIndex]['note'] = ctrl.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showOpenOrdersModal() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Danh sách Đơn đang mở (Chưa thanh toán)'),
        content: SizedBox(
          width: 650,
          height: 400,
          child: openOrders.isEmpty
              ? const Center(child: Text('Không có đơn nào đang lưu.'))
              : ListView.separated(
                  itemCount: openOrders.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, idx) {
                    final ord = openOrders[idx];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.shade800,
                        child: const Icon(Icons.restaurant, color: Colors.white),
                      ),
                      title: Text('${ord['table_name']}  •  ${currency.format(ord['total'])} đ',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      subtitle: Text('Giờ mở đơn: ${ord['created_at']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              final rawList = jsonDecode(ord['items_json'].toString()) as List;
                              final decoded = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                              setState(() {
                                currentOrderId = ord['id'] as int;
                                currentTableName = ord['table_name'].toString();
                                cart = decoded;
                              });
                              Navigator.pop(context);
                            },
                            child: const Text('Mở đơn / Tính tiền'),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final db = await LocalDatabase.db;
                              await db.delete('orders', where: 'id = ?', whereArgs: [ord['id']]);
                              await _loadData();
                              if (mounted) Navigator.pop(context);
                            },
                          )
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
        ],
      ),
    );
  }

  void _showAddProductDialog() {
    final catCtrl = TextEditingController(text: 'Bánh Cuốn Nóng');
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm món mới vào Menu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: catCtrl, decoration: const InputDecoration(labelText: 'Danh mục')),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên món')),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Giá bán (VNĐ)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty && priceCtrl.text.isNotEmpty) {
                final db = await LocalDatabase.db;
                await db.insert('products', {
                  'category': catCtrl.text.trim(),
                  'name': nameCtrl.text.trim(),
                  'price': int.tryParse(priceCtrl.text.trim()) ?? 0,
                });
                await _loadData();
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Thêm món'),
          ),
        ],
      ),
    );
  }

  Future<void> _showReportAndExportModal() async {
    final db = await LocalDatabase.db;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final paidOrders = await db.query(
      'orders',
      where: "status = 'PAID' AND created_at LIKE ?",
      whereArgs: ['$today%'],
      orderBy: 'id DESC',
    );

    int totalRevenue = 0;
    int cashTotal = 0;
    int transferTotal = 0;

    for (var o in paidOrders) {
      int t = o['total'] as int;
      totalRevenue += t;
      if (o['payment_method'] == 'Tiền mặt') {
        cashTotal += t;
      } else {
        transferTotal += t;
      }
    }

    final webhookCtrl = TextEditingController(text: googleSheetWebhookUrl);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Báo cáo Doanh thu Hôm nay ($today)'),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _summaryCard('Tổng số đơn', '${paidOrders.length} đơn', Colors.blueGrey),
                    _summaryCard('Tiền mặt', '${currency.format(cashTotal)} đ', Colors.green),
                    _summaryCard('Chuyển khoản', '${currency.format(transferTotal)} đ', Colors.blue),
                    _summaryCard('TỔNG DOANH THU', '${currency.format(totalRevenue)} đ', Colors.deepOrange),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Cấu hình Google Apps Script Webhook (Tự động đổ vào Google Sheets):',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: webhookCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'https://script.google.com/macros/s/.../exec',
                  ),
                  onChanged: (val) => googleSheetWebhookUrl = val.trim(),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            icon: const Icon(Icons.print),
            label: const Text('In Báo Cáo Kết Ca (K80)'),
            onPressed: () async {
              await SunmiPrinter.initPrinter();
              await SunmiPrinter.startTransactionPrint(true);
              await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
              await SunmiPrinter.printText('BÁO CÁO KẾT CA ($today)',
                  style: SunmiStyle(fontSize: SunmiFontSize.LG, bold: true));
              await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
              await SunmiPrinter.printText('------------------------------------------------');
              await SunmiPrinter.printText('Tổng số đơn đã thanh toán: ${paidOrders.length}');
              await SunmiPrinter.printText('Doanh thu Tiền mặt:      ${currency.format(cashTotal)} đ');
              await SunmiPrinter.printText('Doanh thu Chuyển khoản:  ${currency.format(transferTotal)} đ');
              await SunmiPrinter.printText('------------------------------------------------');
              await SunmiPrinter.printText('TỔNG DOANH THU:          ${currency.format(totalRevenue)} đ',
                  style: SunmiStyle(fontSize: SunmiFontSize.LG, bold: true));
              await SunmiPrinter.lineWrap(4);
              await SunmiPrinter.cut();
              await SunmiPrinter.exitTransactionPrint(true);
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            icon: const Icon(Icons.file_download),
            label: const Text('Xuất file CSV vào máy Sunmi'),
            onPressed: () async {
              final path = await _exportToCsv(paidOrders, today);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã lưu CSV tại: $path')),
                );
              }
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Đồng bộ tất cả lên Google Sheets'),
            onPressed: () async {
              googleSheetWebhookUrl = webhookCtrl.text.trim();
              for (var ord in paidOrders) {
                if (ord['synced'] == 0 && googleSheetWebhookUrl.isNotEmpty) {
                  await _syncSingleOrderToGoogleSheets(ord['id'] as int, ord);
                }
              }
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã đồng bộ dữ liệu lên Google Sheets!')),
                );
              }
            },
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<String> _exportToCsv(List orderList, String exportDate) async {
    final dir = await getExternalStorageDirectory();
    final file = File('${dir!.path}/DoanhThu_$exportDate.csv');

    StringBuffer csv = StringBuffer();
    csv.write('\uFEFF');
    csv.writeln('Mã Đơn,Thời Gian,Bàn/Kênh,Phương Thức,Tổng Tiền,Chi Tiết Món');

    for (var o in orderList) {
      final rawItems = jsonDecode(o['items_json'].toString()) as List;
      final itemSummary = rawItems.map((i) => '${i['name']} (x${i['qty']})').join('; ');
      csv.writeln(
          '${o['id']},"${o['created_at']}","${o['table_name']}","${o['payment_method']}",${o['total']},"$itemSummary"');
    }

    await file.writeAsString(csv.toString());
    return file.path;
  }
}
