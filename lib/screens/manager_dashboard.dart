import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({super.key});

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  final _firestore = FirebaseFirestore.instance;

  final TextEditingController _groupController = TextEditingController();
  final TextEditingController _countController = TextEditingController();

  String _managerName = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fetchManagerName();
  }

  Future<void> _fetchManagerName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() => _managerName = doc.data()?['name'] ?? '');
      }
    } catch (e) {
      debugPrint('Error fetching name: $e');
    }
  }

  Future<void> _addStock() async {
    final uid   = FirebaseAuth.instance.currentUser!.uid;
    final group = _groupController.text.trim().toUpperCase();
    final count = int.tryParse(_countController.text.trim()) ?? 0;

    if (group.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a blood group')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _firestore
          .collection('blood_banks')
          .doc(uid)
          .collection('inventory')
          .doc(group)
          .set({
        'group'    : group,
        'count'    : count,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated: $group → $count units'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
      _groupController.clear();
      _countController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (mounted) setState(() => _saving = false);
  }

  void _viewInventory() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InventorySheet(firestore: _firestore, uid: uid),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
  }

  @override
  void dispose() {
    _groupController.dispose();
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user        = FirebaseAuth.instance.currentUser;
    final displayName =
        _managerName.isNotEmpty ? _managerName : (user?.email ?? '');

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text('Blood Bank Manager'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── PROFILE CARD ──────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.redAccent.shade100,
                      child: Text(
                        _managerName.isNotEmpty
                            ? _managerName[0].toUpperCase()
                            : 'M',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.redAccent),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Welcome back,',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey)),
                        Text(
                          displayName,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── SECTION LABEL ─────────────────────────────
              const Text(
                'Manage Stock',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54),
              ),

              const SizedBox(height: 12),

              // ── MAIN CARD ─────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [

                    // Blood Group field
                    TextField(
                      controller: _groupController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Blood Group',
                        prefixIcon: const Icon(Icons.bloodtype_outlined,
                            color: Colors.redAccent),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Colors.redAccent),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Units field
                    TextField(
                      controller: _countController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Units Available',
                        prefixIcon: const Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.redAccent),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Colors.redAccent),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Update Stock button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _addStock,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              Colors.redAccent.withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white),
                              )
                            : const Text('Update Stock',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // View Inventory button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _viewInventory,
                        icon: const Icon(Icons.remove_red_eye_outlined,
                            color: Colors.redAccent, size: 20),
                        label: const Text('View Inventory',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.redAccent)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: Colors.redAccent, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// INVENTORY BOTTOM SHEET
// ─────────────────────────────────────────────────────────
class _InventorySheet extends StatelessWidget {
  final FirebaseFirestore firestore;
  final String uid;

  const _InventorySheet({required this.firestore, required this.uid});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text('My Blood Inventory',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: firestore
                  .collection('blood_banks')
                  .doc(uid)
                  .collection('inventory')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: Colors.redAccent));
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bloodtype,
                            size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        const Text('No stock added yet.',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                final docs = snap.data!.docs
                  ..sort((a, b) {
                    final aG =
                        (a.data() as Map)['group'] as String? ?? '';
                    final bG =
                        (b.data() as Map)['group'] as String? ?? '';
                    return aG.compareTo(bG);
                  });

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade100),
                  itemBuilder: (context, i) {
                    final data =
                        docs[i].data() as Map<String, dynamic>;
                    final group =
                        data['group'] as String? ?? '?';
                    final count =
                        (data['count'] as num?)?.toInt() ?? 0;
                    final isLow = count < 5;

                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isLow
                                  ? Colors.red.shade50
                                  : Colors.green.shade50,
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(group,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isLow
                                          ? Colors.red.shade700
                                          : Colors.green.shade700)),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('Blood Group $group',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87)),
                                Text(
                                  isLow
                                      ? 'Low stock — restock soon'
                                      : 'Sufficient stock',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: isLow
                                          ? Colors.red.shade400
                                          : Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isLow
                                  ? Colors.red.shade50
                                  : Colors.green.shade50,
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                  color: isLow
                                      ? Colors.red.shade200
                                      : Colors.green.shade200),
                            ),
                            child: Text('$count units',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isLow
                                        ? Colors.red.shade700
                                        : Colors.green.shade700)),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}