import 'package:flutter/material.dart';

import '../models/mission.dart';
import 'formatting.dart';

class ProofDialog extends StatelessWidget {
  const ProofDialog({super.key, required this.point});

  final MissionPoint point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Proof — ${point.label}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProofRow(
                icon: Icons.place,
                label: 'Stop location',
                value: point.address ??
                    '${point.location.latitude.toStringAsFixed(6)}, ${point.location.longitude.toStringAsFixed(6)}',
              ),
              if (point.arrivedAt != null)
                ProofRow(
                  icon: Icons.location_on,
                  label: 'Arrived',
                  value: formatClockTime(point.arrivedAt!),
                ),
              if (point.checkedIn)
                ProofRow(
                  icon: Icons.fingerprint,
                  label: 'Checked in',
                  value: formatClockTime(point.checkedInAt!),
                ),
              if (point.completedAt != null)
                ProofRow(
                  icon: Icons.check_circle,
                  label: 'Completed',
                  value: formatClockTime(point.completedAt!),
                ),
              if (point.proofs.isEmpty && !point.checkedIn)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No proof captured yet.',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                ),
              for (final proof in point.proofs) ...[
                if (proof.type != ProofType.checkin) ...[
                  const Divider(),
                  switch (proof.type) {
                    ProofType.photo => _PhotoProofRow(proof: proof),
                    ProofType.note => _NoteProofRow(proof: proof, theme: theme),
                    _ => const SizedBox.shrink(),
                  },
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class _PhotoProofRow extends StatelessWidget {
  const _PhotoProofRow({required this.proof});

  final MissionProof proof;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProofRow(
          icon: Icons.camera_alt,
          label: 'Photo',
          value: proof.fileUrl ?? 'unknown',
        ),
        if (proof.location != null)
          ProofRow(
            icon: Icons.gps_fixed,
            label: 'GPS',
            value:
                '${proof.location!.latitude.toStringAsFixed(6)}, ${proof.location!.longitude.toStringAsFixed(6)}',
          ),
        if (proof.accuracyMeters != null)
          ProofRow(
            icon: Icons.my_location,
            label: 'Accuracy',
            value: '±${proof.accuracyMeters!.toStringAsFixed(1)}m',
          ),
      ],
    );
  }
}

class _NoteProofRow extends StatelessWidget {
  const _NoteProofRow({required this.proof, required this.theme});

  final MissionProof proof;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProofRow(
          icon: Icons.note,
          label: 'Note',
          value: formatClockTime(proof.capturedAt),
        ),
        const SizedBox(height: 4),
        Text(
          '"${proof.note}"',
          style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
        ),
        if (proof.location != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ProofRow(
              icon: Icons.gps_fixed,
              label: 'GPS',
              value:
                  '${proof.location!.latitude.toStringAsFixed(6)}, ${proof.location!.longitude.toStringAsFixed(6)}',
            ),
          ),
        if (proof.accuracyMeters != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ProofRow(
              icon: Icons.my_location,
              label: 'Accuracy',
              value: '±${proof.accuracyMeters!.toStringAsFixed(1)}m',
            ),
          ),
      ],
    );
  }
}

class ProofRow extends StatelessWidget {
  const ProofRow({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
