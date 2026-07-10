#!/usr/bin/env python3
import argparse
import os
import sys
import time


SCRIPTING_MODULES = r"C:\ProgramData\Blackmagic Design\DaVinci Resolve\Support\Developer\Scripting\Modules"
SCRIPT_LIB = r"C:\Program Files\Blackmagic Design\DaVinci Resolve\fusionscript.dll"


def load_resolve():
    if SCRIPTING_MODULES not in sys.path:
        sys.path.append(SCRIPTING_MODULES)
    if os.path.exists(SCRIPT_LIB):
        os.environ.setdefault("RESOLVE_SCRIPT_LIB", SCRIPT_LIB)

    import DaVinciResolveScript as dvr_script

    return dvr_script.scriptapp("Resolve")


def connect(timeout_seconds):
    deadline = time.time() + timeout_seconds
    last_error = None

    while time.time() < deadline:
        try:
            resolve = load_resolve()
            if resolve:
                manager = resolve.GetProjectManager()
                if manager:
                    return resolve, manager
        except Exception as exc:
            last_error = exc
        time.sleep(1)

    if last_error:
        raise RuntimeError(f"Resolve scripting unavailable: {last_error}")
    raise RuntimeError("Resolve scripting unavailable")


def is_valid_drp(path):
    return bool(path and os.path.exists(path) and os.path.isfile(path) and os.path.getsize(path) > 0)


def ensure_project(manager, project_name, project_folder, drp_path):
    project = manager.LoadProject(project_name)
    if project:
        return project, "loaded"

    if is_valid_drp(drp_path) and manager.ImportProject(drp_path, project_name):
        project = manager.LoadProject(project_name)
        if project:
            return project, "imported"

    project = manager.CreateProject(project_name, project_folder)
    if project:
        return project, "created"

    project = manager.LoadProject(project_name)
    if project:
        return project, "loaded"

    raise RuntimeError(f"Could not load or create Resolve project: {project_name}")


def export_project(manager, project_name, drp_path):
    if not drp_path:
        return False

    os.makedirs(os.path.dirname(drp_path), exist_ok=True)
    temp_path = drp_path + ".tmp"
    try:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        ok = manager.ExportProject(project_name, temp_path, True)
        if ok and os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
            os.replace(temp_path, drp_path)
            return True
    finally:
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--action", choices=["open", "export"], required=True)
    parser.add_argument("--project-name", required=True)
    parser.add_argument("--project-folder", required=True)
    parser.add_argument("--drp-path", required=True)
    parser.add_argument("--timeout", type=int, default=45)
    args = parser.parse_args()

    _, manager = connect(args.timeout)

    if args.action == "open":
        project, status = ensure_project(manager, args.project_name, args.project_folder, args.drp_path)
        manager.SaveProject()
        exported = export_project(manager, project.GetName(), args.drp_path)
        print(f"status={status}; exported={str(exported).lower()}")
        return 0

    project = manager.LoadProject(args.project_name)
    if not project:
        raise RuntimeError(f"Resolve project not found: {args.project_name}")
    manager.SaveProject()
    exported = export_project(manager, project.GetName(), args.drp_path)
    if not exported:
        raise RuntimeError("Failed to export Resolve project")
    print("status=exported")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
