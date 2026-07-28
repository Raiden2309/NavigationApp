import 'package:flutter/material.dart';

import '../models/mission.dart';
import '../services/mission_engine.dart';
import 'formatting.dart';

class StopActions extends StatelessWidget {
  const StopActions({super.key, required this.engine, required this.stop});

  final MissionEngine engine;
  final MissionPoint stop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!stop.checkedIn)
              ActionButton(
                icon: Icons.fingerprint,
                label: 'Check In',
                color: Colors.green,
                onPressed: () => engine.checkIn(),
              ),
            if (stop.checkedIn)
              ActionButton(
                icon: Icons.fingerprint,
                label: 'Checked In',
                color: Colors.green,
                enabled: false,
                onPressed: () {},
              ),
            ActionButton(
              icon: Icons.camera_alt,
              label: 'Upload Photo',
              color: Colors.blue,
              onPressed: () => _uploadPhoto(context),
            ),
            ActionButton(
              icon: Icons.note_add,
              label: 'Add Note',
              color: Colors.amber,
              onPressed: () => _addNote(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (stop.proofs.isNotEmpty) ...[
          Text('Proof captured:', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          ...stop.proofs.map((proof) => ProofTile(proof: proof)),
          const SizedBox(height: 8),
        ],
        FilledButton.icon(
          onPressed: stop.canComplete ? () => engine.completeCurrentStop() : null,
          icon: const Icon(Icons.check),
          label: const Text('Complete Stop'),
        ),
        if (!stop.canComplete)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _missingProofsText(stop),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  String _missingProofsText(MissionPoint stop) {
    final missing = <String>[];
    if (!stop.checkedIn) missing.add('check-in');
    if (!stop.proofs.any((p) => p.type == ProofType.photo)) missing.add('photo');
    if (!stop.proofs.any((p) => p.type == ProofType.note)) missing.add('note');
    return 'Missing: ${missing.join(', ')}';
  }

  void _uploadPhoto(BuildContext context) {
    final fileUrl = 'photos/proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
    engine.uploadPhoto(fileUrl);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Photo captured: $fileUrl'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addNote(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter a note...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      engine.addNote(result);
    }
  }
}

class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18, color: enabled ? color : Colors.grey),
        label: Text(label, style: TextStyle(color: enabled ? color : Colors.grey)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: enabled ? color.withValues(alpha: 0.5) : Colors.grey),
        ),
      ),
    );
  }
}

class ProofTile extends StatelessWidget {
  const ProofTile({super.key, required this.proof});

  final MissionProof proof;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (proof.type) {
      ProofType.checkin => (Icons.fingerprint, 'Check-in at ${formatClockTime(proof.capturedAt)}'),
      ProofType.photo => (Icons.camera_alt, 'Photo: ${proof.fileUrl ?? 'unknown'}'),
      ProofType.note => (Icons.note, 'Note: ${proof.note ?? ''}'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
