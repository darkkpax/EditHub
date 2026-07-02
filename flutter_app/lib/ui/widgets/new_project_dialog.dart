import 'package:flutter/material.dart';

import '../../theme.dart';
import '../design/glass_surface.dart';
import '../design/motion.dart';

typedef CreateProjectCallback =
    Future<void> Function(String name, List<String> urls, String editor);

/// Height shared by the three stacked controls (Name / Footage / Create) so
/// they read as one equal-sized set.
const double _kFieldHeight = 44;

// Bundled logos (were network URLs that rotted -> generic fallback icons).
const _editorLogos = {
  'davinci': 'assets/editors/davinci.png',
  'premiere': 'assets/editors/premiere.png',
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
    return TweenAnimationBuilder<double>(
      key: const Key('project-create-popover'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: .9 + .1 * value,
        alignment: Alignment.bottomRight,
        child: SizedBox(
          width: 300,
          child: GlassSurface(
            blur: 30,
            radius: 20,
            scrim: .42,
            frost: .13,
            shadow: true,
            padding: const EdgeInsets.all(14),
            child: Opacity(opacity: value.clamp(0, 1), child: child),
          ),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Round project-type toggle (replaces the old close X).
            Align(
              alignment: Alignment.centerRight,
              child: _EditorToggle(
                editor: _editor,
                onToggle: () => setState(
                  () => _editor = _editor == 'davinci' ? 'premiere' : 'davinci',
                ),
              ),
            ),
            const SizedBox(height: 8),
            _Field(
              key: const Key('project-name'),
              controller: _name,
              hint: 'Name',
              autofocus: true,
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
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0x14FFFFFF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
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
        borderRadius: BorderRadius.circular(13),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38,
        height: 38,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
        ),
        child: Image.asset(_editorLogos[editor]!, fit: BoxFit.contain),
      ),
    ),
  );
}
