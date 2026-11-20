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

String toBanglaDigits(String value) {
  const english = '0123456789';
  const bangla = '০১২৩৪৫৬৭৮৯';
  for (var i = 0; i < english.length; i++) {
    value = value.replaceAll(english[i], bangla[i]);
  }
  return value;
}

double? parseAmount(String value) => double.tryParse(normalizeDigits(value));

String formatAmount(double amount) {
  final rounded = amount.roundToDouble();
  final result = (amount - rounded).abs() < 0.000001
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  return toBanglaDigits(result);
}

String formatBanglaDate(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? toBanglaDigits(value) : toBanglaDigits(DateFormat('dd-MM-yyyy').format(date));
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

  void showTxModal(String type, {String? presetShop}) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String currentShop = presetShop ?? (shops.isNotEmpty ? shops.first : '');
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

  void showShopDetails(String shop) {
    final items = transactions.where((tx) => tx.shop == shop).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: const Color(0xFFF3F6FB),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.84,
          child: Column(children: [
            const SizedBox(height: 12),
            Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(8))),
            Padding(padding: const EdgeInsets.fromLTRB(20, 18, 12, 14), child: Row(children: [
              Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFFDDF3EE), borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.storefront_rounded, color: Color(0xFF087F75))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shop, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF172B4D))),
                const Text('দোকানের সম্পূর্ণ হিসাব', style: TextStyle(fontSize: 12, color: Color(0xFF77869A))),
              ])),
              IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded)),
            ])),
            Container(margin: const EdgeInsets.symmetric(horizontal: 18), padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF142B4A), Color(0xFF087F75)]), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('বর্তমান বাকি', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  SizedBox(height: 4), Text('এই দোকানের মোট পাওনা', style: TextStyle(color: Colors.white60, fontSize: 11)),
                ]),
                Text('৳ ${formatAmount(calculateShopDue(shop))}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              ])),
            Padding(padding: const EdgeInsets.fromLTRB(20, 17, 20, 8), child: Row(children: [
              const Expanded(child: Text('লেনদেনের বিবরণ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF172B4D)))),
              Text('${toBanglaDigits(items.length.toString())}টি', style: const TextStyle(fontSize: 12, color: Color(0xFF7B8798))),
            ])),
            Expanded(child: items.isEmpty
              ? const Center(child: Text('এখনো কোনো লেনদেন নেই', style: TextStyle(color: Color(0xFF7B8798))))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 12), itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final tx = items[index]; final due = tx.type == 'due';
                    return Container(padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE7EDF4))),
                      child: Row(children: [
                        Container(width: 38, height: 38, decoration: BoxDecoration(color: due ? const Color(0xFFFFEEEE) : const Color(0xFFE4F5F0), borderRadius: BorderRadius.circular(12)),
                          child: Icon(due ? Icons.south_west_rounded : Icons.north_east_rounded, color: due ? const Color(0xFFD94F55) : const Color(0xFF087F75))),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tx.note.isEmpty ? (due ? 'বাকি নিয়েছি' : 'টাকা পরিশোধ') : tx.note, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF26364D))),
                          const SizedBox(height: 3), Text(formatBanglaDate(tx.date), style: const TextStyle(fontSize: 11, color: Color(0xFF8793A5))),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('${due ? '+' : '−'} ৳${formatAmount(tx.amount)}', style: TextStyle(fontWeight: FontWeight.w800, color: due ? const Color(0xFFD94F55) : const Color(0xFF087F75))),
                          IconButton(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFF9AA6B5)),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
                                title: const Text('হিসাব মুছে ফেলবেন?'),
                                content: const Text('এই লেনদেনটি মুছে ফেললে তা আর তালিকায় দেখা যাবে না।'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('না')),
                                  ElevatedButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('মুছে ফেলুন')),
                                ],
                              ));
                              if (confirmed == true) { transactions.removeWhere((t) => t.id == tx.id); await saveData(); if (sheetContext.mounted) Navigator.pop(sheetContext); }
                            }),
                        ]),
                      ]));
                  })),
            Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 16), child: Row(children: [
              Expanded(child: FilledButton.icon(onPressed: () => showTxModal('due', presetShop: shop), icon: const Icon(Icons.add_rounded), label: const Text('বাকি যোগ'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD94F55), padding: const EdgeInsets.symmetric(vertical: 13)))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton.icon(onPressed: () => showTxModal('payment', presetShop: shop), icon: const Icon(Icons.check_rounded), label: const Text('পরিশোধ'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F75), padding: const EdgeInsets.symmetric(vertical: 13)))),
            ])),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        elevation: 0, backgroundColor: const Color(0xFF142B4A), foregroundColor: Colors.white, titleSpacing: 18,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('আমার বাকির খাতা', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text('সহজে রাখুন প্রতিদিনের হিসাব', style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w400)),
        ]),
        actions: [IconButton(icon: const Icon(Icons.cloud_sync_rounded), onPressed: showBackupDialog, tooltip: 'ডাটা ব্যাকআপ'), const SizedBox(width: 5)],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(17, 17, 17, 24), children: [
        Container(padding: const EdgeInsets.all(21),
          decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF142B4A), Color(0xFF1D526B), Color(0xFF087F75)]),
            borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x22142B4A), blurRadius: 18, offset: Offset(0, 8))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('সব দোকান মিলিয়ে মোট বাকি', style: TextStyle(color: Colors.white70, fontSize: 13))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.13), borderRadius: BorderRadius.circular(20)),
                child: const Row(children: [Icon(Icons.account_balance_wallet_outlined, size: 13, color: Color(0xFF8DE0D0)), SizedBox(width: 5), Text('হিসাবের সারাংশ', style: TextStyle(color: Colors.white, fontSize: 10))])),
            ]),
            const SizedBox(height: 9),
            Text('৳ ${formatAmount(calculateTotalDue())}', style: const TextStyle(color: Colors.white, fontSize: 33, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16), Container(height: 1, color: Colors.white24), const SizedBox(height: 13),
            Row(children: [
              Expanded(child: _modernSummary(Icons.storefront_outlined, 'মোট দোকান', toBanglaDigits(shops.length.toString()))),
              Container(width: 1, height: 34, color: Colors.white24),
              Expanded(child: _modernSummary(Icons.receipt_long_outlined, 'মোট লেনদেন', toBanglaDigits(transactions.length.toString()))),
            ]),
          ])),
        const SizedBox(height: 20),
        Row(children: [
          const Expanded(child: Text('দ্রুত হিসাব', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF172B4D)))),
          TextButton.icon(onPressed: addShopDialog, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('দোকান যোগ')),
        ]),
        Row(children: [
          Expanded(child: _modernAction('বাকি নিয়েছি', 'নতুন বাকি এন্ট্রি', Icons.add_shopping_cart_rounded, const Color(0xFFD94F55), () {
            if (shops.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('আগে নিজের পছন্দমতো একটি দোকান যোগ করুন।'))); addShopDialog(); } else { showTxModal('due'); }
          })),
          const SizedBox(width: 11),
          Expanded(child: _modernAction('পরিশোধ', 'টাকা জমা এন্ট্রি', Icons.payments_rounded, const Color(0xFF087F75), () {
            if (shops.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('আগে নিজের পছন্দমতো একটি দোকান যোগ করুন।'))); addShopDialog(); } else { showTxModal('payment'); }
          })),
        ]),
        const SizedBox(height: 22),
        Row(children: [
          const Expanded(child: Text('আমার দোকানগুলো', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF172B4D)))),
          Text('${toBanglaDigits(shops.length.toString())}টি', style: const TextStyle(fontSize: 12, color: Color(0xFF7B8798))),
        ]),
        const SizedBox(height: 10),
        if (shops.isEmpty)
          Container(padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE7EDF4))),
            child: Column(children: [
              Container(width: 58, height: 58, decoration: const BoxDecoration(color: Color(0xFFE4F5F0), shape: BoxShape.circle), child: const Icon(Icons.storefront_rounded, color: Color(0xFF087F75), size: 28)),
              const SizedBox(height: 12), const Text('এখনো কোনো দোকান যোগ করা হয়নি', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF26364D))),
              const SizedBox(height: 5), const Text('শুরু করতে প্রথম দোকানটি যোগ করুন', style: TextStyle(fontSize: 12, color: Color(0xFF8793A5))),
              const SizedBox(height: 14), FilledButton.icon(onPressed: addShopDialog, icon: const Icon(Icons.add), label: const Text('প্রথম দোকান যোগ করুন')),
            ]))
        else
          ...shops.map((shop) {
            final due = calculateShopDue(shop);
            final count = transactions.where((tx) => tx.shop == shop).length;
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(color: Colors.white, borderRadius: BorderRadius.circular(18),
              child: InkWell(borderRadius: BorderRadius.circular(18), onTap: () => showShopDetails(shop),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE7EDF4))),
                  child: Row(children: [
                    Container(width: 45, height: 45, decoration: BoxDecoration(color: const Color(0xFFE4F5F0), borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.storefront_rounded, color: Color(0xFF087F75), size: 23)),
                    const SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(shop, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF24364B))),
                      const SizedBox(height: 4), Text('${toBanglaDigits(count.toString())}টি লেনদেন • বিস্তারিত দেখতে চাপ দিন', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF8A96A6))),
                    ])),
                    const SizedBox(width: 7),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('৳ ${formatAmount(due)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: due > 0 ? const Color(0xFFD94F55) : const Color(0xFF087F75))),
                      const Text('বর্তমান বাকি', style: TextStyle(fontSize: 9, color: Color(0xFF8A96A6))),
                    ]),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA6B5), size: 20),
                  ])))),
            );
          }),
        const SizedBox(height: 8),
        Center(child: Text('আপনার হিসাব, আপনার নিয়ন্ত্রণে', style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade300))),
      ]),
    );
  }

  Widget _modernSummary(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, color: const Color(0xFF8DE0D0), size: 19), const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ]),
    ]);
  }

  Widget _modernAction(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Material(color: Colors.white, borderRadius: BorderRadius.circular(17),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(17),
        child: Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE7EDF4))),
          child: Row(children: [
            Container(width: 39, height: 39, decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 21)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF26364D))),
              const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 9, color: Color(0xFF8A96A6))),
            ])),
          ])),
      ));
  }

}