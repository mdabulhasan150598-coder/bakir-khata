import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

String normalizeDigits(String value) {
  const bangla = '০১২৩৪৫৬৭৮৯';
  const english = '0123456789';
  for (var i = 0; i < bangla.length; i++) {
    value = value.replaceAll(bangla[i], english[i]);
  }
  return value.replaceAll(',', '').replaceAll('٬', '').trim();
}

double? parseAmount(String value) => double.tryParse(normalizeDigits(value));

String formatAmount(double amount) {
  final rounded = amount.roundToDouble();
  return (amount - rounded).abs() < 0.000001
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BakiKhataApp());
}

class BakiKhataApp extends StatelessWidget {
  const BakiKhataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'আমার বাকির খাতা',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF087E83),
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF6F8FA),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE7EDF2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF087E83), width: 1.5)),
        ),
        appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
      ),
      home: const HomeScreen(),
    );
  }
}

class TxItem {
  final String id;
  final String shop;
  final String type; // 'due' (বাকি) or 'payment' (পরিশোধ)
  final double amount;
  final String note;
  final String date;

  TxItem({
    required this.id,
    required this.shop,
    required this.type,
    required this.amount,
    required this.note,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'shop': shop,
    'type': type,
    'amount': amount,
    'note': note,
    'date': date,
  };

  factory TxItem.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final shop = map['shop'];
    final type = map['type'];
    final amount = map['amount'];
    final note = map['note'] ?? '';
    final date = map['date'];
    if (id is! String || id.isEmpty ||
        shop is! String || shop.isEmpty ||
        (type != 'due' && type != 'payment') ||
        amount is! num || !amount.toDouble().isFinite || amount <= 0 ||
        note is! String || date is! String) {
      throw const FormatException('Invalid transaction data');
    }
    DateTime? parsedDate = DateTime.tryParse(date);
    if (parsedDate == null) throw const FormatException('Invalid transaction date');
    return TxItem(
      id: id,
      shop: shop,
      type: type,
      amount: amount.toDouble(),
      note: note,
      date: date,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<String> shops = [];
  List<TxItem> transactions = [];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shopList = prefs.getStringList('shops');
      final txListJson = prefs.getString('txs');
      var loadedTransactions = <TxItem>[];
      if (txListJson != null) {
        final decoded = jsonDecode(txListJson);
        if (decoded is! List) throw const FormatException('Invalid saved transactions');
        loadedTransactions = decoded.map((e) {
          if (e is! Map) throw const FormatException('Invalid saved transaction');
          return TxItem.fromMap(Map<String, dynamic>.from(e));
        }).toList();
      }
      // নতুন ইনস্টলে কোনো ডিফল্ট দোকান থাকবে না। তবে পুরোনো দোকানে হিসাব থাকলে
      // সেই হিসাব হারানো ঠেকাতে সংশ্লিষ্ট নামটি পুরোনো রেকর্ডের জন্য রাখা হবে।
      final loadedShops = (shopList ?? <String>[])
          .where((s) =>
              (s != 'কালাম স্টোর' && s != 'মুদি দোকান') ||
              loadedTransactions.any((tx) => tx.shop == s))
          .toList();
      if (loadedShops.any((s) => s.trim().isEmpty) ||
          loadedShops.toSet().length != loadedShops.length) {
        throw const FormatException('Invalid shop list');
      }
      if (!mounted) return;
      setState(() {
        shops = loadedShops;
        transactions = loadedTransactions;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('সংরক্ষিত ডাটা পড়তে সমস্যা হয়েছে। ব্যাকআপ থাকলে রিস্টোর করুন।')),
      );
    }
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('shops', shops);
    final txListMap = transactions.map((e) => e.toMap()).toList();
    await prefs.setString('txs', jsonEncode(txListMap));
    if (mounted) setState(() {});
  }

  double calculateTotalDue() {
    double total = 0;
    for (var tx in transactions) {
      if (tx.type == 'due') total += tx.amount;
      if (tx.type == 'payment') total -= tx.amount;
    }
    return total;
  }

  double calculateShopDue(String shop) {
    double total = 0;
    for (var tx in transactions.where((t) => t.shop == shop)) {
      if (tx.type == 'due') total += tx.amount;
      if (tx.type == 'payment') total -= tx.amount;
    }
    return total;
  }

  void openShopDetails(String shop) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShopDetailsScreen(
          shop: shop,
          transactions: () => transactions.where((tx) => tx.shop == shop).toList(),
          balance: () => calculateShopDue(shop),
          onAddTransaction: (type) => showTxModal(type, initialShop: shop),
          onDeleteTransaction: deleteTransaction,
        ),
      ),
    );
  }

  Future<void> deleteTransaction(TxItem tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('হিসাব মুছে ফেলবেন?'),
        content: const Text('এই লেনদেনটি মুছে ফেললে তা আর তালিকায় দেখা যাবে না।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('না'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('মুছে ফেলুন'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      transactions.removeWhere((item) => item.id == tx.id);
      await saveData();
    }
  }

  void addShopDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('নতুন দোকান যোগ করুন'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'যেমন: ভাই ভাই ফার্মেসি'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty || shops.contains(name)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(name.isEmpty ? 'দোকানের নাম লিখুন।' : 'এই দোকানটি আগে থেকেই আছে।')),
                );
                return;
              }
              shops.add(name);
              await saveData();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('যোগ করুন'),
          ),
        ],
      ),
    );
  }

  Future<void> showTxModal(String type, {String? initialShop}) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String currentShop = initialShop != null && shops.contains(initialShop)
        ? initialShop
        : (shops.isNotEmpty ? shops.first : '');
    DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type == 'due' ? '➕ বাকি পণ্য যোগ করুন' : '💳 টাকা পরিশোধ এন্ট্রি',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: currentShop.isNotEmpty ? currentShop : null,
                decoration: const InputDecoration(labelText: 'দোকান নির্বাচন'),
                items: shops.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => currentShop = val);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month, color: Colors.teal),
                title: const Text('তারিখ'),
                subtitle: Text(DateFormat('dd-MM-yyyy').format(selectedDate)),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    helpText: 'লেনদেনের তারিখ নির্বাচন করুন',
                  );
                  if (picked != null) setModalState(() => selectedDate = picked);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'টাকার পরিমাণ (৳)', prefixText: '৳ '),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'পণ্যের নাম / বিবরণ (ঐচ্ছিক)'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: type == 'due' ? Colors.red : Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final amount = parseAmount(amountCtrl.text) ?? 0;
                    if (amount <= 0 || currentShop.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('সঠিক টাকার পরিমাণ লিখুন এবং দোকান নির্বাচন করুন।')),
                      );
                      return;
                    }
                    transactions.add(TxItem(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      shop: currentShop,
                      type: type,
                      amount: amount,
                      note: noteCtrl.text.trim(),
                      date: DateFormat('yyyy-MM-dd').format(selectedDate),
                    ));
                    await saveData();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('সংরক্ষণ করুন', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> exportBackupFile() async {
    try {
      final backupData = {
        'app': 'bakir_khata',
        'version': 1,
        'saved_at': DateTime.now().toIso8601String(),
        'shops': shops,
        'txs': transactions.map((e) => e.toMap()).toList(),
      };
      final jsonBytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(backupData),
      );
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/bakir_khata_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsBytes(jsonBytes, flush: true);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'আমার বাকির খাতার JSON ব্যাকআপ',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('শেয়ার মেনু থেকে Drive বা Files নির্বাচন করে JSON ব্যাকআপ সেভ করুন।'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ব্যাকআপ তৈরি করতে সমস্যা হয়েছে: $e')),
        );
      }
    }
  }

  Future<void> restoreFromJsonFile() async {
    try {
      final pickedResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (pickedResult == null || pickedResult.files.isEmpty) return;

      final pickedFile = pickedResult.files.single;
      final fileBytes = pickedFile.bytes ??
          (pickedFile.path != null
              ? await File(pickedFile.path!).readAsBytes()
              : null);
      if (fileBytes == null || fileBytes.isEmpty) {
        throw const FormatException('JSON ফাইলটি পড়া যাচ্ছে না।');
      }

      final jsonText = utf8.decode(fileBytes, allowMalformed: false);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map ||
          (decoded['app'] != null && decoded['app'] != 'bakir_khata') ||
          decoded['shops'] is! List ||
          decoded['txs'] is! List) {
        throw const FormatException('এটি আমার বাকির খাতার সঠিক JSON ব্যাকআপ নয়।');
      }
      if (decoded['app'] == 'bakir_khata' && decoded['version'] != 1) {
        throw const FormatException('ব্যাকআপ ফাইলের ভার্সন সমর্থিত নয়।');
      }

      final restoredShops = List<String>.from(decoded['shops']);
      if (restoredShops.any((s) => s.trim().isEmpty) ||
          restoredShops.toSet().length != restoredShops.length) {
        throw const FormatException('ব্যাকআপে দোকানের নামের তথ্য সঠিক নয়।');
      }
      final restoredTransactions = (decoded['txs'] as List).map((item) {
        if (item is! Map) {
          throw const FormatException('ব্যাকআপে লেনদেনের তথ্য সঠিক নয়।');
        }
        final tx = TxItem.fromMap(Map<String, dynamic>.from(item));
        if (!restoredShops.contains(tx.shop)) {
          throw const FormatException('কোনো লেনদেনের দোকানের নাম ব্যাকআপে পাওয়া যায়নি।');
        }
        return tx;
      }).toList();

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('JSON ব্যাকআপ রিস্টোর করবেন?'),
          content: Text(
            '${pickedFile.name} ফাইল থেকে ${restoredTransactions.length}টি লেনদেন এবং '
            '${restoredShops.length}টি দোকানের তথ্য ফিরিয়ে আনা হবে। '
            'এতে এই ফোনের বর্তমান হিসাব ব্যাকআপের তথ্য দিয়ে প্রতিস্থাপিত হবে।',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('বাতিল'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('রিস্টোর করুন'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final oldShops = prefs.getStringList('shops');
      final oldTxs = prefs.getString('txs');
      try {
        await prefs.setStringList('shops', restoredShops);
        await prefs.setString(
          'txs',
          jsonEncode(restoredTransactions.map((e) => e.toMap()).toList()),
        );
      } catch (_) {
        if (oldShops == null) {
          await prefs.remove('shops');
        } else {
          await prefs.setStringList('shops', oldShops);
        }
        if (oldTxs == null) {
          await prefs.remove('txs');
        } else {
          await prefs.setString('txs', oldTxs);
        }
        rethrow;
      }

      setState(() {
        shops = restoredShops;
        transactions = restoredTransactions;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('আলহামদুলিল্লাহ! JSON ব্যাকআপ সফলভাবে রিস্টোর হয়েছে।')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('JSON রিস্টোর করতে সমস্যা: $e')),
        );
      }
    }
  }

  void showBackupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ডাটা ব্যাকআপ ও রিস্টোর'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'মিয়াপাড়া চাঁদা অ্যাপের মতো সরাসরি JSON ফাইল দিয়ে ব্যাকআপ ও রিস্টোর করুন।',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save_alt),
                label: const Text('JSON ব্যাকআপ সেভ করুন'),
                onPressed: () {
                  Navigator.pop(ctx);
                  exportBackupFile();
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.restore),
                label: const Text('JSON ফাইল থেকে রিস্টোর করুন'),
                onPressed: () {
                  Navigator.pop(ctx);
                  restoreFromJsonFile();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalPaid = transactions
        .where((t) => t.type == 'payment')
        .fold<double>(0, (sum, t) => sum + t.amount);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FB),
        foregroundColor: const Color(0xFF172B4D),
        elevation: 0,
        titleSpacing: 20,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('আমার বাকির খাতা',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('আপনার সব দোকানের হিসাব এক জায়গায়',
                style: TextStyle(fontSize: 11, color: Color(0xFF718096), fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              icon: const Icon(Icons.backup_outlined),
              onPressed: showBackupDialog,
              tooltip: 'ডাটা ব্যাকআপ',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF173B5E), Color(0xFF087E83)],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(color: Color(0x25173B5E), blurRadius: 22, offset: Offset(0, 10)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 21),
                        ),
                        const SizedBox(width: 10),
                        const Text('সব দোকানে মোট বাকি',
                            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '৳ ${formatAmount(calculateTotalDue())}',
                      style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 18),
                    Container(height: 1, color: Colors.white.withOpacity(0.18)),
                    const SizedBox(height: 13),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _summaryItem(Icons.storefront_outlined, '${shops.length}', 'মোট দোকান'),
                        _summaryItem(Icons.payments_outlined, '৳ ${formatAmount(totalPaid)}', 'মোট পরিশোধ'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('আমার দোকানসমূহ',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF172B4D))),
                  TextButton.icon(
                    onPressed: addShopDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('দোকান যোগ'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF087E83)),
                  ),
                ],
              ),
              if (shops.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    children: [
                      const Icon(Icons.store_mall_directory_outlined, size: 38, color: Color(0xFF8AA1B5)),
                      const SizedBox(height: 10),
                      const Text('এখনো কোনো দোকান যোগ করা হয়নি',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF34465A))),
                      const SizedBox(height: 4),
                      const Text('যে দোকানে বাকি আছে, সেটি প্রথমে যোগ করুন',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF8493A5))),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: addShopDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('প্রথম দোকান যোগ করুন'),
                      ),
                    ],
                  ),
                )
              else
                ...shops.map((shop) {
                  final balance = calculateShopDue(shop);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => openShopDetails(shop),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFFE9EEF4),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF5F4),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.storefront_rounded, color: Color(0xFF087E83)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(shop, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF26384A))),
                                    const SizedBox(height: 3),
                                    const Text('বিস্তারিত ও লেনদেন দেখতে চাপ দিন',
                                        style: const TextStyle(fontSize: 10, color: Color(0xFF8A98A8))),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('৳ ${formatAmount(balance)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800, fontSize: 15,
                                        color: balance > 0 ? const Color(0xFFD45B50) : const Color(0xFF16856D),
                                      )),
                                  const Text('বর্তমান বাকি', style: TextStyle(fontSize: 10, color: Color(0xFF8A98A8))),
                                ],
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right, color: Color(0xFF9AA8B7)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Color(0x10000000), blurRadius: 14, offset: Offset(0, -4))],
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('বাকি নিয়েছি'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD65D52), foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: () {
                    if (shops.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('আগে একটি দোকান যোগ করুন।')));
                      addShopDialog();
                    } else {
                      showTxModal('due');
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('টাকা পরিশোধ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF087E83), foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: () {
                    if (shops.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('আগে একটি দোকান যোগ করুন।')));
                      addShopDialog();
                    } else {
                      showTxModal('payment');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryItem(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 17),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

class ShopDetailsScreen extends StatefulWidget {
  final String shop;
  final List<TxItem> Function() transactions;
  final double Function() balance;
  final Future<void> Function(String type) onAddTransaction;
  final Future<void> Function(TxItem tx) onDeleteTransaction;

  const ShopDetailsScreen({
    super.key,
    required this.shop,
    required this.transactions,
    required this.balance,
    required this.onAddTransaction,
    required this.onDeleteTransaction,
  });

  @override
  State<ShopDetailsScreen> createState() => _ShopDetailsScreenState();
}

class _ShopDetailsScreenState extends State<ShopDetailsScreen> {
  Future<void> _add(String type) async {
    await widget.onAddTransaction(type);
    if (mounted) setState(() {});
  }

  Future<void> _delete(TxItem tx) async {
    await widget.onDeleteTransaction(tx);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.transactions().reversed.toList();
    final dueTotal = items
        .where((tx) => tx.type == 'due')
        .fold<double>(0, (sum, tx) => sum + tx.amount);
    final paidTotal = items
        .where((tx) => tx.type == 'payment')
        .fold<double>(0, (sum, tx) => sum + tx.amount);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FB),
        foregroundColor: const Color(0xFF172B4D),
        title: Text(widget.shop,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF173B5E), Color(0xFF087E83)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x25173B5E),
                  blurRadius: 20,
                  offset: Offset(0, 9),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('এই দোকানে বর্তমান বাকি',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Text('৳ ${formatAmount(widget.balance())}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _detailTotal('মোট বাকি নিয়েছি', dueTotal,
                          const Color(0xFFFFD6D1)),
                    ),
                    Expanded(
                      child: _detailTotal('মোট পরিশোধ', paidTotal,
                          const Color(0xFFBDEBDD)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _add('due'),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('বাকি নিয়েছি'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD65D52),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _add('payment'),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('টাকা পরিশোধ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF087E83),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('লেনদেনের বিবরণ',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF172B4D))),
              Text('${items.length}টি',
                  style: const TextStyle(
                      color: Color(0xFF8493A5), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18)),
              child: const Column(
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 36, color: Color(0xFF9AA8B7)),
                  SizedBox(height: 9),
                  Text('এই দোকানে এখনো কোনো লেনদেন নেই',
                      style: TextStyle(
                          color: Color(0xFF718096),
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('উপরের বাটন থেকে প্রথম হিসাবটি যোগ করুন',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF8493A5))),
                ],
              ),
            )
          else
            ...items.map((tx) {
              final isDue = tx.type == 'due';
              return Container(
                margin: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17)),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isDue
                          ? const Color(0xFFFFEFED)
                          : const Color(0xFFE8F6F1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      isDue
                          ? Icons.shopping_bag_outlined
                          : Icons.check_circle_outline,
                      color: isDue
                          ? const Color(0xFFD45D52)
                          : const Color(0xFF16856D),
                    ),
                  ),
                  title: Text(
                    tx.note.isEmpty
                        ? (isDue ? 'বাকি পণ্য নিয়েছি' : 'টাকা পরিশোধ')
                        : tx.note,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${isDue ? "বাকি নেওয়া" : "পরিশোধ"} • ${DateFormat('dd-MM-yyyy').format(DateTime.parse(tx.date))}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF8493A5)),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${isDue ? "+" : "−"} ৳${formatAmount(tx.amount)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: isDue
                              ? const Color(0xFFD45D52)
                              : const Color(0xFF16856D),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert,
                            color: Color(0xFF8795A5), size: 20),
                        onSelected: (value) {
                          if (value == 'delete') _delete(tx);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'delete', child: Text('হিসাব মুছুন')),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _detailTotal(String label, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        Text('৳ ${formatAmount(amount)}',
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

