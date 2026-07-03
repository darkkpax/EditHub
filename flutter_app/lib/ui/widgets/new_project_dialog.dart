import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme.dart';
import '../design/glass_surface.dart';
import '../design/motion.dart';

typedef CreateProjectCallback =
    Future<void> Function(String name, List<String> urls, String editor);

/// Shared height for every control so the stack reads as one set.
const double _kFieldHeight = 40;

// Monochrome brand glyphs (simple-icons), tinted — not the full colored app
// icons, per request.
const _editorLogos = {
  'davinci': 'assets/editors/davinci.svg',
  'premiere': 'assets/editors/premiere.svg',
};

class NewProjectPopover extends StatefulWidget {
  const NewProjectPopover({
    super.key,
    required this.onCreate,
    required this.onClose,
  });

  final CreateProjectCallback onCreate;
  final VoidCallback onClose;

  @override
  State<NewProjectPopover> createState() => _NewProjectPopoverState();
}

class _NewProjectPopoverState extends State<NewProjectPopover> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String _editor = 'davinci';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _loading) return;
    final url = _url.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onCreate(_name.text.trim(), url.isEmpty ? const [] : [url], _editor);
      widget.onClose();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('project-create-popover'),
      width: 300,
      child: GlassSurface(
        blur: 16,
        radius: 20,
        scrim: .5,
        frost: .07,
        shadow: true,
        padding: const EdgeInsets.all(12),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _EditorToggle(
                    editor: _editor,
                    onToggle: () => setState(
                      () => _editor =
                          _editor == 'davinci' ? 'premiere' : 'davinci',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Field(
                      key: const Key('project-name'),
                      controller: _name,
                      hint: 'Name',
                      autofocus: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _Field(
                key: const Key('project-url'),
                controller: _url,
                hint: 'Footage',
                onSubmitted: (_) => _create(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.bad, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              _CreateButton(loading: _loading, onTap: _create),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.controller,
    required this.hint,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _kFieldHeight,
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      onSubmitted: onSubmitted,
      textAlignVertical: TextAlignVertical.center,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0x14FFFFFF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
        ),
      ),
    ),
  );
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressableScale(
    onTap: loading ? null : onTap,
    child: Container(
      height: _kFieldHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Text(
              'Create',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
    ),
  );
}

class _EditorToggle extends StatelessWidget {
  const _EditorToggle({required this.editor, required this.onToggle});
  final String editor;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: editor == 'davinci' ? 'DaVinci Resolve' : 'Premiere Pro',
    child: PressableScale(
      onTap: onToggle,
      child: Container(
        width: _kFieldHeight,
        height: _kFieldHeight,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
        ),
        child: SvgPicture.asset(
          _editorLogos[editor]!,
          fit: BoxFit.contain,
          colorFilter: const ColorFilter.mode(AppColors.txt, BlendMode.srcIn),
        ),
      ),
    ),
  );
}
