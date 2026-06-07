import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  String _formatDate(Timestamp? ts) {
    if (ts == null) return 'Date unknown';
    final dt = ts.toDate();
    final h  = dt.hour.toString().padLeft(2, '0');
    final m  = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year}  $h:$m';
  }

  // FIX 2 — load all driver names in one batch instead of
  // one FutureBuilder per row (avoids per-row Firestore reads on every rebuild)
  Future<Map<String, String>> _fetchDriverNames(
      List<QueryDocumentSnapshot> docs) async {
    final ids = docs
        .map((d) => (d.data() as Map)['assignedAmbulance'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final Map<String, String> names = {};
    for (final id in ids) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('ambulances')
            .doc(id)
            .get();
        if (snap.exists) {
          names[id] = (snap.data()?['name'] as String?) ?? 'Unknown Driver';
        }
      } catch (_) {}
    }
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My History'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [

          // ── AMBULANCE HISTORY ───────────────────────────
          _SectionLabel(label: '🚑  Ambulance History'),
          const SizedBox(height: 10),

          StreamBuilder<QuerySnapshot>(
            // FIX 1 — removed .orderBy() to avoid composite index requirement.
            // We sort client-side instead, which works without any Firestore index.
            stream: FirebaseFirestore.instance
                .collection('emergency_requests')
                .where('userId', isEqualTo: uid)
                .snapshots(),
            builder: (context, snap) {
              // FIX 3 — centered loading indicator
              if (snap.connectionState == ConnectionState.waiting) {
                return const _LoadingRow();
              }

              if (snap.hasError) {
                return _EmptyRow(
                  message: 'Error loading history.\n'
                      'Make sure Firestore index exists for '
                      'emergency_requests (userId + createdAt).',
                );
              }

              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const _EmptyRow(message: 'No ambulance requests yet.');
              }

              // FIX 1 — client-side sort by createdAt descending
              docs.sort((a, b) {
                final aTs = (a.data() as Map)['createdAt'] as Timestamp?;
                final bTs = (b.data() as Map)['createdAt'] as Timestamp?;
                if (aTs == null || bTs == null) return 0;
                return bTs.compareTo(aTs);
              });

              // FIX 2 — single batch fetch for all driver names
              return FutureBuilder<Map<String, String>>(
                future: _fetchDriverNames(docs),
                builder: (context, driverSnap) {
                  final driverNames = driverSnap.data ?? {};

                  return Column(
                    children: docs.map((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      final assignedId =
                          (d['assignedAmbulance'] as String?) ?? '';

                      // FIX 4 — guard empty assignedAmbulance
                      final driverName = assignedId.isEmpty
                          ? 'Not assigned'
                          : (driverNames[assignedId] ?? 'Loading...');

                      final status = (d['status'] as String?) ?? 'unknown';
                      final date   = _formatDate(d['createdAt'] as Timestamp?);

                      return _HistoryCard(
                        icon: Icons.local_hospital,
                        iconColor: Colors.redAccent,
                        title: driverName,
                        status: status,
                        date: date,
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ── BLOOD HISTORY ────────────────────────────────
          _SectionLabel(label: '🩸  Blood History'),
          const SizedBox(height: 10),

          StreamBuilder<QuerySnapshot>(
            // FIX 1 — same: no orderBy, sort client-side
            stream: FirebaseFirestore.instance
                .collection('blood_requests')
                .where('userId', isEqualTo: uid)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _LoadingRow();
              }

              if (snap.hasError) {
                return _EmptyRow(
                  message: 'Error loading blood history.\n'
                      'Make sure Firestore index exists for '
                      'blood_requests (userId + createdAt).',
                );
              }

              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const _EmptyRow(message: 'No blood requests yet.');
              }

              // Client-side sort
              docs.sort((a, b) {
                final aTs = (a.data() as Map)['createdAt'] as Timestamp?;
                final bTs = (b.data() as Map)['createdAt'] as Timestamp?;
                if (aTs == null || bTs == null) return 0;
                return bTs.compareTo(aTs);
              });

              return Column(
                children: docs.map((doc) {
                  final d    = doc.data() as Map<String, dynamic>;
                  final bg   = (d['bloodGroup'] as String?) ?? '?';
                  final units = d['units']?.toString() ?? '?';
                  final bank = (d['bankName'] as String?) ?? 'Unknown bank';
                  final date = _formatDate(d['createdAt'] as Timestamp?);
                  final status = (d['status'] as String?) ?? 'unknown';

                  return _HistoryCard(
                    icon: Icons.bloodtype,
                    iconColor: const Color(0xFFB71C1C),
                    title: '$bg  ·  $units units',
                    subtitle: bank,
                    status: status,
                    date: date,
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String message;
  const _EmptyRow({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 14)),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String status;
  final String date;

  const _HistoryCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.status,
    required this.date,
  });

  Color get _statusColor {
    switch (status) {
      case 'completed': return Colors.green;
      case 'assigned':  return Colors.blue;
      case 'pending':
      case 'awaiting_driver': return Colors.orange;
      case 'cancelled': return Colors.red;
      default:          return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.grey)),
                ],
                const SizedBox(height: 4),
                Text(date,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _statusColor.withOpacity(0.3)),
            ),
            child: Text(
              status,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _statusColor),
            ),
          ),
        ],
      ),
    );
  }
}