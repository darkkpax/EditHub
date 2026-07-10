from pathlib import Path


glass = Path("Sources/EditHub/DesignSystem/GlassUI.swift").read_text(encoding="utf-8")
project_list = Path("Sources/EditHub/Views/ProjectListView.swift").read_text(encoding="utf-8")
project_detail = Path("Sources/EditHub/Views/ProjectDetailView.swift").read_text(encoding="utf-8")

assert "struct FrostedHeaderStrip" in glass
assert "FrostedHeaderStrip()" in project_list
assert "FrostedHeaderStrip()" in project_detail
assert "frame(height: 116)" in project_list
assert "frame(height: 116)" in project_detail
print("macOS search and project headers share the 116pt frosted strip")
