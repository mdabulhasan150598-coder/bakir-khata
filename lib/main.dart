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
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
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
  String selectedShop = 'ALL';

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
      // পুরোনো ডিফল্ট দোকান দুটি আর স্বয়ংক্রিয়ভাবে দেখানো হবে না।
      final loadedShops = (shopList ?? <String>[])
          .where((s) => s != 'কালাম স্টোর' && s != 'মুদি দোকান')
          .toList();
      if (loadedShops.any((s) => s.trim().isEmpty) ||
          loadedShops.toSet().length != loadedShops.length) {
        throw const FormatException('Invalid shop list');
      }
      var loadedTransactions = <TxItem>[];
      if (txListJson != null) {
        final decoded = jsonDecode(txListJson);
        if (decoded is! List) throw const FormatException('Invalid saved transactions');
        loadedTransactions = decoded.map((e) {
          if (e is! Map) throw const FormatException('Invalid saved transaction');
          return TxItem.fromMap(Map<String, dynamic>.from(e));
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        shops = loadedShops;
        transactions = loadedTransactions;
        if (selectedShop != 'ALL' && !shops.contains(selectedShop)) {
          selectedShop = 'ALL';
        }
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

  void showTxModal(String type) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String currentShop = shops.isNotEmpty ? shops.first : '';
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
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'আমার বাকির খাতার JSON ব্যাকআপ',
        ),
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
        selectedShop = 'ALL';
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
    final filteredTxs = selectedShop == 'ALL'
        ? transactions
        : transactions.where((t) => t.shop == selectedShop).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('📒 আমার বাকির খাতা', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: showBackupDialog,
            tooltip: 'ডাটা ব্যাকআপ',
          ),
        ],
      ),
      body: Column(
        children: [
          // Total Balance Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.teal, Color(0xFF0D9488)]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('আমার মোট বাকি দেনা', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 6),
                    Text(
                      '৳ ${formatAmount(calculateTotalDue())}',
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: addShopDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('দোকান'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.teal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),

          // Shop Filter Tabs
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ChoiceChip(
                  label: const Text('সব দোকান'),
                  selected: selectedShop == 'ALL',
                  onSelected: (val) => setState(() => selectedShop = 'ALL'),
                ),
                const SizedBox(width: 8),
                ...shops.map((s) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$s (৳${formatAmount(calculateShopDue(s))})'),
                    selected: selectedShop == s,
                    onSelected: (val) => setState(() => selectedShop = s),
                  ),
                )),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Transaction List
          Expanded(
            child: filteredTxs.isEmpty
                ? const Center(child: Text('কোনো হিসাব পাওয়া যায়নি', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredTxs.length,
                    reverse: true,
                    itemBuilder: (ctx, idx) {
                      final tx = filteredTxs[idx];
                      final isDue = tx.type == 'due';
                      return Card(
                        elevation: 0.5,
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isDue ? Colors.red.shade50 : Colors.teal.shade50,
                            child: Icon(
                              isDue ? Icons.arrow_upward : Icons.arrow_downward,
                              color: isDue ? Colors.red : Colors.teal,
                              size: 20,
                            ),
                          ),
                          title: Text(tx.shop, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${tx.note.isEmpty ? "বিবরণ নেই" : tx.note} • ${tx.date}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${isDue ? "+" : "-"} ৳${formatAmount(tx.amount)}',
                                style: TextStyle(
                                  color: isDue ? Colors.red : Colors.teal,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                onPressed: () async {
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
                                    transactions.removeWhere((t) => t.id == tx.id);
                                    await saveData();
                                  }
                                },
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('বাকি নিয়েছি'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    if (shops.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('আগে নিজের পছন্দমতো একটি দোকান যোগ করুন।')),
                      );
                      addShopDialog();
                    } else {
                      showTxModal('due');
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('পরিশোধ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    if (shops.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('আগে নিজের পছন্দমতো একটি দোকান যোগ করুন।')),
                      );
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
}