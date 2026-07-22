import json
import subprocess
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk


DOCKER_CONTAINER = "arches"

DATATYPE_COMPATIBILITY = {
    "string": {"string", "non-localized-string", "number"},
    "non-localized-string": {"string", "non-localized-string", "number"},
    "number": {"number", "string", "non-localized-string"},
    "domain-value": {"domain-value", "concept", "concept-list"},
    "concept": {"concept", "concept-list", "domain-value"},
    "concept-list": {"concept", "concept-list", "domain-value"},
    "resource-instance": {"resource-instance", "resource-instance-list"},
    "resource-instance-list": {"resource-instance", "resource-instance-list"},
    "date": {"date"},
    "boolean": {"boolean"},
    "file-list": {"file-list"},
    "geojson-feature-collection": {"geojson-feature-collection", "non-localized-string"},
}

def datatypes_compatible(source_type, target_type):
    return target_type in DATATYPE_COMPATIBILITY.get(source_type, {source_type})


def run_docker_command(args):
    result = subprocess.run(
        args,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )

    if result.returncode != 0:
        raise RuntimeError(result.stderr or result.stdout)

    return result.stdout   
def run_manage_json(*args):
    cmd = [
        "docker",
        "exec",
        DOCKER_CONTAINER,
        "python",
        "manage.py",
        "migrate_data",
        *args,
    ]

    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )

    if result.returncode != 0:
        raise RuntimeError(result.stderr or result.stdout)

    return json.loads(result.stdout)


def graph_label(graph):
    return f'{graph["name"]} | {graph["graph_id"][:8]}'


def node_label(node):
    display_name = node.get("path") or node["name"]
    return f'{display_name} | {node["datatype"]} | {node["node_id"][:8]}'


class MappingEditor(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title("Arches Resource Mapping Editor")
        self.geometry("1200x700")

        self.graphs = []
        self.graph_by_label = {}

        self.payload = None
        self.mapping_by_source = {}
        self.target_by_label = {}
        self.target_label_by_id = {}

        self.source_graph = tk.StringVar()
        self.target_graph = tk.StringVar()
        self.target_choice = tk.StringVar()
        self.enabled_var = tk.BooleanVar(value=True)

        self.build_ui()
        self.load_graphs()

    def build_ui(self):
        top = ttk.Frame(self, padding=8)
        top.pack(fill="x")

        ttk.Label(top, text="Source").pack(side="left")
        self.source_graph_combo  = ttk.Combobox(top, textvariable=self.source_graph, width=45, state="readonly")
        self.source_graph_combo.pack(side="left", padx=(4, 12))

        ttk.Label(top, text="Target").pack(side="left")
        self.target_graph_combo = ttk.Combobox(top, textvariable=self.target_graph, width=45, state="readonly")
        self.target_graph_combo.pack(side="left", padx=(4, 12))

        ttk.Button(top, text="Load Mapping", command=self.load_mapping).pack(side="left")
        ttk.Button(top, text="Save JSON", command=self.save_json).pack(side="left", padx=(8, 0))
        ttk.Button(top, text="Migrate", command=self.run_migration).pack(side="left", padx=(8, 0))
        main = ttk.PanedWindow(self, orient="horizontal")
        main.pack(fill="both", expand=True, padx=8, pady=8)

        left = ttk.Frame(main)
        right = ttk.Frame(main, padding=8)
        main.add(left, weight=3)
        main.add(right, weight=1)

        columns = ("source", "source_type", "target", "status")
        self.tree = ttk.Treeview(left, columns=columns, show="headings", selectmode="browse")

        self.tree.heading("source", text="Source node")
        self.tree.heading("source_type", text="Type")
        self.tree.heading("target", text="Target node")
        self.tree.heading("status", text="Status")

        self.tree.column("source", width=360)
        self.tree.column("source_type", width=110)
        self.tree.column("target", width=360)
        self.tree.column("status", width=100)

        self.tree.pack(fill="both", expand=True)
        self.tree.bind("<<TreeviewSelect>>", self.on_select)

        ttk.Label(right, text="Selected source").pack(anchor="w")
        self.source_info = tk.Text(right, height=7, wrap="word")
        self.source_info.pack(fill="x", pady=(4, 12))

        ttk.Label(right, text="Target node").pack(anchor="w")
        self.target_combo = ttk.Combobox(right, textvariable=self.target_choice, state="readonly", height=40)
        self.target_combo.pack(fill="x", pady=(4, 24))

        ttk.Checkbutton(right, text="Enabled", variable=self.enabled_var).pack(anchor="w")

        ttk.Button(right, text="Assign", command=self.assign_target).pack(fill="x", pady=(16, 4))
        ttk.Button(right, text="Clear", command=self.clear_target).pack(fill="x")

    def load_graphs(self):
        try:
            self.graphs = run_manage_json("--list-graphs")
        except Exception as exc:
            messagebox.showerror("Error", str(exc))
            return

        labels = [graph_label(graph) for graph in self.graphs]
        self.graph_by_label = {
            graph_label(graph): graph
            for graph in self.graphs
        }

        self.source_graph_combo["values"] = labels
        self.target_graph_combo["values"] = labels

    def load_mapping(self):
        source = self.graph_by_label.get(self.source_graph.get())
        target = self.graph_by_label.get(self.target_graph.get())

        if not source or not target:
            messagebox.showwarning("Missing selection", "Choose source and target resource models.")
            return

        try:
            self.payload = run_manage_json(
                "--suggest-mapping",
                source["graph_id"],
                target["graph_id"],
            )
        except Exception as exc:
            messagebox.showerror("Error", str(exc))
            return

        self.mapping_by_source = {
            item["source_node_id"]: item
            for item in self.payload["mappings"]
        }

        self.target_by_label = {
            node_label(node): node
            for node in self.payload["target_nodes"]
        }
        self.target_label_by_id = {
            node["node_id"]: node_label(node)
            for node in self.payload["target_nodes"]
        }

        self.target_combo["values"] = [""] + list(self.target_by_label.keys())
        self.refresh_tree()

    def refresh_tree(self):
        self.tree.delete(*self.tree.get_children())

        for mapping in self.payload["mappings"]:
            self.tree.insert(
                "",
                "end",
                iid=mapping["source_node_id"],
                values=(
                    (mapping.get("source_node_path") or mapping["source_node_name"]),
                    mapping["source_datatype"],
                    mapping.get("target_node_name", ""),
                    self.mapping_status(mapping),
                ),
            )

    def mapping_status(self, mapping):
        if not mapping.get("enabled", True):
            return "DISABLED"
        if not mapping.get("target_node_id"):
            return "UNMAPPED"
        if mapping.get("special_transform"):
            return "OK"
        if not datatypes_compatible(mapping["source_datatype"], mapping.get("target_datatype")):
            return "MISMATCH"
        return "OK"

    def on_select(self, _event=None):
        selected = self.tree.selection()
        if not selected:
            return

        source_node_id = selected[0]
        mapping = self.mapping_by_source[source_node_id]

        self.source_info.delete("1.0", "end")
        self.source_info.insert(
            "1.0",
            "\n".join([
                f'Name: {mapping["source_node_name"]}',
                f'Type: {mapping["source_datatype"]}',
                f'Node ID: {mapping["source_node_id"]}',
            ]),
        )

        self.enabled_var.set(mapping.get("enabled", True))
        self.target_choice.set(self.target_label_by_id.get(mapping.get("target_node_id"), ""))

    def assign_target(self):
        selected = self.tree.selection()
        if not selected:
            return

        source_node_id = selected[0]
        mapping = self.mapping_by_source[source_node_id]
        target = self.target_by_label.get(self.target_choice.get())

        if not target:
            self.clear_target()
            return
        mapping["target_node_path"] = target.get("path", target["name"])
        mapping["target_node_id"] = target["node_id"]
        mapping["target_node_name"] = target["name"]
        mapping["target_datatype"] = target["datatype"]
        mapping["enabled"] = self.enabled_var.get()

        self.refresh_tree()
        self.tree.selection_set(source_node_id)

    def clear_target(self):
        selected = self.tree.selection()
        if not selected:
            return

        source_node_id = selected[0]
        mapping = self.mapping_by_source[source_node_id]

        mapping["target_node_id"] = ""
        mapping["target_node_name"] = ""
        mapping["target_datatype"] = ""
        mapping["enabled"] = False

        self.refresh_tree()
        self.tree.selection_set(source_node_id)

    def save_json(self):
        if not self.payload:
            messagebox.showwarning("Nothing to save", "Load mapping first.")
            return

        path = filedialog.asksaveasfilename(
            defaultextension=".json",
            filetypes=[("JSON files", "*.json")],
        )

        if not path:
            return

        Path(path).write_text(
            json.dumps(self.payload, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

        messagebox.showinfo("Saved", f"Mapping saved:\n{path}")
     
    def run_migration(self):
        if not self.payload:
            messagebox.showwarning("Nothing to migrate", "Load mapping first.")
            return

        if not messagebox.askyesno("Run migration", "Run migration with --apply?"):
            return

        update_existing = messagebox.askyesno(
            "Update existing",
            "Update existing target resources matched by legacy ID? This replaces their mapped tile values.",
        )

        local_tmp = Path("resource_mapping_tmp.json")
        container_path = "/tmp/resource_mapping_tmp.json"

        local_tmp.write_text(
            json.dumps(self.payload, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

        try:
            run_docker_command([
                "docker", "cp",
                str(local_tmp),
                f"{DOCKER_CONTAINER}:{container_path}",
            ])

            migrate_cmd = [
                "docker", "exec", DOCKER_CONTAINER,
                "python", "manage.py", "migrate_data",
                "--mapping", container_path,
                "--apply",
            ]
            if update_existing:
                migrate_cmd.append("--update-existing")

            output = run_docker_command(migrate_cmd)

            messagebox.showinfo("Migration complete", output or "Migration complete.")

        except Exception as exc:
            messagebox.showerror("Migration failed", str(exc))

        finally:
            try:
                run_docker_command([
                    "docker", "exec", DOCKER_CONTAINER,
                    "rm", "-f", container_path,
                ])
            except Exception:
                pass

            try:
                local_tmp.unlink()
            except FileNotFoundError:
                pass        


if __name__ == "__main__":
    app = MappingEditor()
    app.mainloop()