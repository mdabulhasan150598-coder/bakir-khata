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
  for (var i = 0; i < english.length; i++) { value = value.replaceAll(english[i], bangla[i]); }
  return value;
}

double? parseAmount(String value) => double.tryParse(normalizeDigits(value));

String formatAmount(double amount) {
  final rounded = amount.roundToDouble();
  final formatted = (amount - rounded).abs() < 0.000001
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  return toBanglaDigits(formatted);
}

String formatBanglaDate(DateTime date) => toBanglaDigits(DateFormat('dd-MM-yyyy').format(date));

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BakiKhataApp());
}

class BakiKhataApp extends StatelessWidget {
  const BakiKhataApp({super.key});

  void showShopDetails(String shop) {
    final shopTxs = transactions.where((tx) => tx.shop == shop).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: const Color(0xFFF4F7FB),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.82,
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(8))),
          Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12), child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.storefront_rounded, color: Color(0xFF0F766E), size: 26)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shop, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF172B4D))),
              const Text('দোকানের সম্পূর্ণ হিসাব', style: TextStyle(fontSize: 12, color: Color(0xFF718096))),
            ])),
            IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
          ])),
          Container(margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF142B4A), Color(0xFF1B4965)]), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('বর্তমান বাকি', style: TextStyle(color: Colors.white70, fontSize: 12)), SizedBox(height: 5),
                Text('এই দোকানের মোট পাওনা', style: TextStyle(color: Colors.white60, fontSize: 11)),
              ]),
              Text('৳ ${formatAmount(calculateShopDue(shop))}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            ])),
          Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 8), child: Row(children: [
            const Expanded(child: Text('লেনদেনের বিবরণ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF172B4D)))),
            Text('${toBanglaDigits(shopTxs.length.toString())}টি লেনদেন', style: const TextStyle(fontSize: 12, color: Color(0xFF718096))),
          ])),
          Expanded(child: shopTxs.isEmpty
            ? const Center(child: Text('এখনো কোনো লেনদেন নেই', style: TextStyle(color: Color(0xFF718096))))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), itemCount: shopTxs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final tx = shopTxs[index]; final due = tx.type == 'due'; final date = DateTime.tryParse(tx.date);
                  return Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      Container(width: 38, height: 38, decoration: BoxDecoration(color: due ? const Color(0xFFFFE8E8) : const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(12)),
                        child: Icon(due ? Icons.south_west_rounded : Icons.north_east_rounded, color: due ? const Color(0xFFDC5252) : const Color(0xFF0F8A78), size: 20)),
                      const SizedBox(width: 11),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tx.note.isEmpty ? (due ? 'বাকি নিয়েছি' : 'টাকা পরিশোধ') : tx.note, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF26364D))),
                        const SizedBox(height: 3),
                        Text(date == null ? toBanglaDigits(tx.date) : formatBanglaDate(date), style: const TextStyle(fontSize: 11, color: Color(0xFF8793A5))),
                      ])),
                      Text('${due ? '+' : '−'} ৳${formatAmount(tx.amount)}', style: TextStyle(fontWeight: FontWeight.w800, color: due ? const Color(0xFFD84D4D) : const Color(0xFF0F8A78))),
                    ]));
                })),
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 18), child: Row(children: [
            Expanded(child: FilledButton.icon(onPressed: () => showTxModal('due', presetShop: shop), icon: const Icon(Icons.add_rounded), label: const Text('বাকি যোগ'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC5252), padding: const EdgeInsets.symmetric(vertical: 13)))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: () => showTxModal('payment', presetShop: shop), icon: const Icon(Icons.check_rounded), label: const Text('পরিশোধ'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F8A78), padding: const EdgeInsets.symmetric(vertical: 13)))),
          ])),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(elevation: 0, backgroundColor: const Color(0xFF142B4A), foregroundColor: Colors.white, titleSpacing: 20,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('আমার বাকির খাতা', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text('সহজে রাখুন প্রতিদিনের হিসাব', style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w400)),
        ]),
        actions: [IconButton(onPressed: showBackupDialog, tooltip: 'ব্যাকআপ ও রিস্টোর', icon: const Icon(Icons.cloud_sync_rounded)), const SizedBox(width: 6)]),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 24), children: [
        Container(padding: const EdgeInsets.all(21),
          decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF142B4A), Color(0xFF1C526B), Color(0xFF0F766E)]),
            borderRadius: BorderRadius.circular(25), boxShadow: const [BoxShadow(color: Color(0x22142B4A), blurRadius: 20, offset: Offset(0, 9))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('সব দোকান মিলিয়ে মোট বাকি', style: TextStyle(color: Colors.white70, fontSize: 13))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.13), borderRadius: BorderRadius.circular(20)),
                child: const Row(children: [Icon(Icons.account_balance_wallet_outlined, size: 13, color: Color(0xFF8DE0D0)), SizedBox(width: 5), Text('হিসাবের সারাংশ', style: TextStyle(color: Colors.white, fontSize: 10))])),
            ]),
            const SizedBox(height: 10),
            Text('৳ ${formatAmount(calculateTotalDue())}', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 0.2)),
            const SizedBox(height: 18), Container(height: 1, color: Colors.white.withOpacity(0.16)), const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _summaryItem(Icons.storefront_outlined, 'মোট দোকান', toBanglaDigits(shops.length.toString()))),
              Container(width: 1, height: 34, color: Colors.white24),
              Expanded(child: _summaryItem(Icons.receipt_long_outlined, 'মোট লেনদেন', toBanglaDigits(transactions.length.toString()))),
            ]),
          ])),
        const SizedBox(height: 20),
        Row(children: [
          const Expanded(child: Text('দ্রুত হিসাব', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF172B4D)))),
          TextButton.icon(onPressed: addShopDialog, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('দোকান যোগ')),
        ]),
        Row(children: [
          Expanded(child: _actionCard(icon: Icons.add_shopping_cart_rounded, title: 'বাকি নিয়েছি', subtitle: 'নতুন বাকি এন্ট্রি', color: const Color(0xFFD94F55),
            onTap: () { if (shops.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('আগে একটি দোকান যোগ করুন।'))); addShopDialog(); } else { showTxModal('due'); } })),
          const SizedBox(width: 12),
          Expanded(child: _actionCard(icon: Icons.payments_rounded, title: 'পরিশোধ', subtitle: 'টাকা জমা এন্ট্রি', color: const Color(0xFF0F8A78),
            onTap: () { if (shops.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('আগে একটি দোকান যোগ করুন।'))); addShopDialog(); } else { showTxModal('payment'); } })),
        ]),
        const SizedBox(height: 23),
        Row(children: [
          const Expanded(child: Text('আমার দোকানগুলো', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF172B4D)))),
          Text('${toBanglaDigits(shops.length.toString())}টি', style: const TextStyle(color: Color(0xFF7B8798), fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 11),
        if (shops.isEmpty)
          Container(padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE6ECF3))),
            child: Column(children: [
              Container(width: 58, height: 58, decoration: const BoxDecoration(color: Color(0xFFE7F4F2), shape: BoxShape.circle), child: const Icon(Icons.storefront_rounded, color: Color(0xFF0F766E), size: 28)),
              const SizedBox(height: 12), const Text('এখনো কোনো দোকান যোগ করা হয়নি', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF26364D))),
              const SizedBox(height: 5), const Text('শুরু করতে প্রথম দোকানটি যোগ করুন', style: TextStyle(fontSize: 12, color: Color(0xFF8793A5))),
              const SizedBox(height: 14), FilledButton.icon(onPressed: addShopDialog, icon: const Icon(Icons.add), label: const Text('প্রথম দোকান যোগ করুন')),
            ]))
        else
          ...shops.map((shop) {
            final due = calculateShopDue(shop); final count = transactions.where((tx) => tx.shop == shop).length;
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(color: Colors.white, borderRadius: BorderRadius.circular(19),
              child: InkWell(borderRadius: BorderRadius.circular(19), onTap: () => showShopDetails(shop),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(19), border: Border.all(color: const Color(0xFFE8EDF4))),
                  child: Row(children: [
                    Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFFE7F4F2), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.storefront_rounded, color: Color(0xFF0F766E), size: 24)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(shop, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF24364B))),
                      const SizedBox(height: 5),
                      Text('${toBanglaDigits(count.toString())}টি লেনদেন  •  বিস্তারিত দেখতে চাপ দিন', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF8A96A6))),
                    ])),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('৳ ${formatAmount(due)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: due > 0 ? const Color(0xFFD94F55) : const Color(0xFF0F8A78))),
                      const Text('বর্তমান বাকি', style: TextStyle(fontSize: 9, color: Color(0xFF8A96A6))),
                    ]),
                    const SizedBox(width: 3), const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA6B5), size: 21),
                  ])),
              )),
            );
          }),
        const SizedBox(height: 8),
        Center(child: Text('আপনার হিসাব, আপনার নিয়ন্ত্রণে', style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade300))),
      ]),
    );
  }

  Widget _summaryItem(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, color: const Color(0xFF8DE0D0), size: 19), const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ]),
    ]);
  }

  Widget _actionCard({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback onTap}) {
    return Material(color: Colors.white, borderRadius: BorderRadius.circular(18),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18),
        child: Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8EDF4))),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withOpacity(0.11), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: color, size: 21)),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF26364D))),
              const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 9, color: Color(0xFF8A96A6))),
            ])),
          ])),
      ));
  }

}