import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'app_menus.dart';
import 'main.dart';
import 'text_direction.dart';

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.initial,
    this.required = true,
    this.secret = false,
    this.lines = 1,
    this.options,
    this.multi = false,
    this.file = false,
    this.number = false,
    this.omitEmpty = false,
    this.hint,
  });
  final String key, label;
  final dynamic initial;
  final bool required, secret, multi, file, number, omitEmpty;
  final int lines;
  final Map<String, String>? options;
  final String? hint;
}

Future<Json?> showActionForm(
  BuildContext context,
  AppController c, {
  required String title,
  required String path,
  String method = 'POST',
  List<FieldSpec> fields = const [],
  Json fixed = const {},
  String? submit,
  bool destructive = false,
}) => showModalBottomSheet<Json>(
  useRootNavigator: true,
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => ActionForm(
    controller: c,
    title: title,
    path: path,
    method: method,
    fields: fields,
    fixed: fixed,
    submit: submit,
    destructive: destructive,
  ),
);

class ActionForm extends StatefulWidget {
  const ActionForm({
    super.key,
    required this.controller,
    required this.title,
    required this.path,
    required this.method,
    required this.fields,
    required this.fixed,
    this.submit,
    this.destructive = false,
  });
  final AppController controller;
  final String title, path, method;
  final List<FieldSpec> fields;
  final Json fixed;
  final String? submit;
  final bool destructive;
  @override
  State<ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<ActionForm> {
  final key = GlobalKey<FormState>();
  final Map<String, TextEditingController> controllers = {};
  final Json selected = {};
  bool busy = false;
  String? error;
  Json fieldErrors = {};
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      if (f.options != null) {
        selected[f.key] = f.multi
            ? List<String>.from(
                (f.initial is List ? f.initial : const []).map((v) => '$v'),
              )
            : (f.initial == null ? null : '${f.initial}');
      } else if (!f.file) {
        controllers[f.key] = TextEditingController(text: value(f.initial));
      }
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void setNested(Json map, String key, dynamic val) {
    final parts = key.split('.');
    if (parts.length == 1) {
      map[key] = val;
    } else {
      map[parts.first] ??= <String, dynamic>{};
      object(map[parts.first]);
      (map[parts.first] as Map<String, dynamic>)[parts.skip(1).join('.')] = val;
    }
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      fieldErrors = {};
    });
    try {
      final data = <String, dynamic>{...widget.fixed};
      for (final f in widget.fields) {
        dynamic val;
        if (f.file) {
          final file = selected[f.key];
          if (file is XFile) {
            val = await MultipartFile.fromFile(file.path, filename: file.name);
          } else {
            continue;
          }
        } else if (f.options != null) {
          val = selected[f.key] ?? (f.multi ? [] : null);
        } else {
          val = controllers[f.key]!.text.trim();
          if (f.number && val != '') val = int.tryParse(val) ?? val;
          if (!f.required && val == '') val = null;
        }
        if (f.omitEmpty &&
            (val == null || val == '' || val is List && val.isEmpty)) {
          continue;
        }
        setNested(data, f.key, val);
      }
      final result = await widget.controller.action(
        widget.method,
        widget.path,
        data,
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          fieldErrors = e.fields;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              for (final f in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: f.file
                      ? OutlinedButton.icon(
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(
                            selected[f.key] is XFile
                                ? (selected[f.key] as XFile).name
                                : f.label,
                          ),
                          onPressed: busy
                              ? null
                              : () async {
                                  final file = await ImagePicker().pickImage(
                                    source: ImageSource.gallery,
                                    maxWidth: 2400,
                                    imageQuality: 90,
                                  );
                                  if (file != null && mounted) {
                                    setState(() => selected[f.key] = file);
                                  }
                                },
                        )
                      : f.multi
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.label),
                            Wrap(
                              spacing: 8,
                              children: f.options!.entries
                                  .map(
                                    (e) => FilterChip(
                                      label: Text(e.value),
                                      selected: (selected[f.key] as List)
                                          .contains(e.key),
                                      onSelected: busy
                                          ? null
                                          : (on) => setState(() {
                                              if (on) {
                                                (selected[f.key] as List).add(
                                                  e.key,
                                                );
                                              } else {
                                                (selected[f.key] as List)
                                                    .remove(e.key);
                                              }
                                            }),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        )
                      : f.options != null
                      ? AppDropdownButtonFormField<String>(
                          initialValue: f.options!.containsKey(selected[f.key])
                              ? selected[f.key]
                              : null,
                          decoration: InputDecoration(labelText: f.label),
                          items: f.options!.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: busy ? null : (v) => selected[f.key] = v,
                          validator: (v) => f.required && v == null
                              ? c.t('Choose an option', 'اختر قيمة')
                              : null,
                        )
                      : AdaptiveTextField(
                          controller: controllers[f.key],
                          field: (direction) => TextFormField(
                            controller: controllers[f.key],
                            textDirection: direction,
                            obscureText: f.secret,
                            maxLines: f.secret ? 1 : f.lines,
                            enabled: !busy,
                            keyboardType: f.number
                                ? TextInputType.number
                                : f.key.contains('email')
                                ? TextInputType.emailAddress
                                : TextInputType.text,
                            textInputAction: f.lines > 1
                                ? TextInputAction.newline
                                : TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: f.label,
                              hintText: f.hint,
                              errorText: fieldErrors[f.key] is List
                                  ? (fieldErrors[f.key] as List).join('\n')
                                  : null,
                            ),
                            validator: (v) =>
                                f.required && (v?.trim().isEmpty ?? true)
                                ? c.t(
                                    'This field is required',
                                    'هذا الحقل مطلوب',
                                  )
                                : null,
                          ),
                        ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: busy ? null : save,
                style: widget.destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                    : null,
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.submit ?? c.t('Save', 'حفظ')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
