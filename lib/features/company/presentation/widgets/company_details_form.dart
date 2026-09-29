import 'package:flutter/material.dart';

import '../../../../core/state/submit_controller.dart';
import '../../data/models/company.dart';

const _companySizes = ['1-10', '11-50', '51-200', '201-1000', '1000+'];

/// Company name / website / industry / … form.
/// [onSubmit] returns an error message, or null on success.
class CompanyDetailsForm extends StatefulWidget {
  final CompanyDetails? initial;
  final String submitLabel;
  final Future<String?> Function(CompanyDetails details) onSubmit;

  const CompanyDetailsForm({
    super.key,
    this.initial,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  State<CompanyDetailsForm> createState() => _CompanyDetailsFormState();
}

class _CompanyDetailsFormState extends State<CompanyDetailsForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _website = TextEditingController(text: widget.initial?.website);
  late final _industry = TextEditingController(text: widget.initial?.industry);
  late final _country = TextEditingController(text: widget.initial?.country);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late String? _size = _companySizes.contains(widget.initial?.companySize)
      ? widget.initial?.companySize
      : null;
  final _submit = SubmitController();

  @override
  void dispose() {
    for (final c in [
      _name,
      _website,
      _industry,
      _country,
      _phone,
      _description,
    ]) {
      c.dispose();
    }
    _submit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    await _submit.run(
      () => widget.onSubmit(
        CompanyDetails(
          name: _name.text.trim(),
          website: text(_website),
          industry: text(_industry),
          companySize: _size,
          country: text(_country),
          phone: text(_phone),
          description: text(_description),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final twoColumns = MediaQuery.sizeOf(context).width >= 560;

    Widget pair(Widget a, Widget b) => twoColumns
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          )
        : Column(children: [a, const SizedBox(height: 12), b]);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Company name *',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().length < 2)
                ? 'Enter at least 2 characters'
                : null,
          ),
          const SizedBox(height: 12),
          pair(
            TextFormField(
              controller: _website,
              decoration: const InputDecoration(
                labelText: 'Website',
                hintText: 'example.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            TextFormField(
              controller: _industry,
              decoration: const InputDecoration(
                labelText: 'Industry',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          pair(
            DropdownButtonFormField<String>(
              initialValue: _size,
              decoration: const InputDecoration(
                labelText: 'Team size',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final s in _companySizes)
                  DropdownMenuItem(value: s, child: Text('$s people')),
              ],
              onChanged: (v) => _size = v,
            ),
            TextFormField(
              controller: _country,
              decoration: const InputDecoration(
                labelText: 'Country',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(
              labelText: 'Contact phone',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'About the company',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            minLines: 2,
            maxLines: 4,
          ),
          // Only the error text and button react to submit state.
          ListenableBuilder(
            listenable: _submit,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_submit.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _submit.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _submit.isBusy ? null : _save,
                    icon: _submit.isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(widget.submitLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
