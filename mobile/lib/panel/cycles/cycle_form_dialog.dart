import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../auth/panel_auth_notifier.dart';
import '../format.dart';
import 'cycle.dart';

/// Opens a new cycle, or edits [cycle]. Pops true when the backend changed.
class CycleFormDialog extends ConsumerStatefulWidget {
  final PanelCycle? cycle;

  const CycleFormDialog({super.key, this.cycle});

  @override
  ConsumerState<CycleFormDialog> createState() => _CycleFormDialogState();
}

class _CycleFormDialogState extends ConsumerState<CycleFormDialog> {
  late DateTime? _closesAt = widget.cycle?.scheduledClosedAt?.toLocal();

  /// Local midnight of the chosen start day.
  late DateTime? _startDay = _dayOf(widget.cycle?.startsAt.toLocal());
  late final _duration = TextEditingController(text: '${widget.cycle?.durationDays ?? defaultDurationDays}');
  String? _error;
  bool _saving = false;

  bool get _editing => widget.cycle != null;

  static DateTime? _dayOf(DateTime? d) => d == null ? null : DateTime(d.year, d.month, d.day);

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  Future<void> _pickClose() async {
    final today = _dayOf(DateTime.now())!;
    final current = _closesAt;
    final date = await showDatePicker(
      context: context,
      helpText: 'Chiusura delle richieste',
      // A closed cycle may keep a date already past, which the picker can't start from.
      initialDate: current != null && !current.isBefore(today) ? current : today.add(const Duration(days: 1)),
      firstDate: today,
      lastDate: today.add(const Duration(days: maxDurationDays)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      helpText: 'Ora di chiusura',
      initialTime: current != null ? TimeOfDay.fromDateTime(current) : const TimeOfDay(hour: 23, minute: 59),
    );
    if (time == null || !mounted) return;
    setState(() => _closesAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickStart() async {
    final today = _dayOf(DateTime.now())!;
    final first = today.add(const Duration(days: 1));
    final fallback = _closesAt == null ? first : _dayOf(_closesAt)!.add(const Duration(days: 1));
    final initial = _startDay ?? fallback;
    final date = await showDatePicker(
      context: context,
      helpText: 'Inizio del percorso',
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: today.add(const Duration(days: maxDurationDays)),
    );
    if (date != null && mounted) setState(() => _startDay = date);
  }

  /// The first problem with the form, checked before calling the backend.
  String? _validate(int? duration) {
    final closesAt = _closesAt;
    final startDay = _startDay;
    if (closesAt == null) return 'Scegli la data di chiusura delle richieste.';
    if (startDay == null) return 'Scegli la data di inizio del percorso.';
    if (duration == null || duration < 1 || duration > maxDurationDays) {
      return 'La durata deve essere tra 1 e $maxDurationDays giorni.';
    }
    final closeChanged = closesAt != widget.cycle?.scheduledClosedAt?.toLocal();
    if (closeChanged && !closesAt.isAfter(DateTime.now())) return 'La data di chiusura deve essere nel futuro.';
    if (closesAt.isAfter(startDay) && (closeChanged || (widget.cycle?.isOpen ?? true))) {
      return 'Le richieste devono chiudersi entro le 00:00 del giorno di inizio.';
    }
    return null;
  }

  /// Only what changed is sent: resending the date of a closed cycle is pointless and
  /// a start date read in another time zone could shift by a day.
  Map<String, dynamic> _changes(int duration) {
    final cycle = widget.cycle;
    final closesAt = _closesAt!;
    final startDay = _startDay!;
    return {
      if (closesAt != cycle?.scheduledClosedAt?.toLocal()) 'scheduledClosedAt': closesAt.toUtc().toIso8601String(),
      if (startDay != _dayOf(cycle?.startsAt.toLocal())) 'startDate': DateFormat('yyyy-MM-dd').format(startDay),
      if (duration != cycle?.durationDays) 'durationDays': duration,
    };
  }

  Future<void> _save() async {
    final duration = int.tryParse(_duration.text.trim());
    final problem = _validate(duration);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final changes = _changes(duration!);
    if (changes.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(panelApiClientProvider);
      if (_editing) {
        await api.patch('/api/cycles/${widget.cycle!.id}', data: changes);
      } else {
        await api.post('/api/cycles/open', data: changes);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is ApiException ? e.message : 'Impossibile salvare il ciclo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final closedCycle = _editing && !widget.cycle!.isOpen;
    return AlertDialog(
      title: Text(_editing ? 'Modifica il ciclo' : 'Apri un ciclo'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateField(
                label: 'Chiusura delle richieste',
                value: _closesAt == null ? 'Scegli data e ora' : formatDateTime(_closesAt!),
                icon: Icons.schedule,
                onPressed: _saving ? null : _pickClose,
              ),
              if (closedCycle)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Una nuova data di chiusura riapre le richieste.', style: theme.textTheme.bodySmall),
                ),
              const SizedBox(height: 16),
              _DateField(
                label: 'Inizio del percorso',
                value: _startDay == null ? 'Scegli la data' : formatDate(_startDay!),
                icon: Icons.event,
                onPressed: _saving ? null : _pickStart,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _duration,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Durata del percorso', suffixText: 'giorni'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_editing ? 'Salva' : 'Apri il ciclo'),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onPressed;

  const _DateField({required this.label, required this.value, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Semantics(
          label: label,
          child: OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(value)),
        ),
      ],
    );
  }
}
