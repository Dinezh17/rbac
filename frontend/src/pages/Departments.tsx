import { useEffect, useState } from "react";
import { api, ApiError } from "../api/client";
import { useAuth } from "../auth/AuthContext";
import { DepartmentFormModal } from "../components/DepartmentFormModal";
import type { Department } from "../types";

export function Departments() {
  const { hasPermission } = useAuth();
  const [departments, setDepartments] = useState<Department[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<Department | null>(null);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function refresh() {
    setLoading(true);
    api
      .departments()
      .then(setDepartments)
      .finally(() => setLoading(false));
  }

  useEffect(refresh, []);

  function handleSaved(dept: Department) {
    setEditing(null);
    setCreating(false);
    refresh();
    void dept;
  }

  async function handleDelete(dept: Department) {
    if (!confirm(`Delete ${dept.department_name}? This fails if any employees or sections still reference it.`)) {
      return;
    }
    setError(null);
    try {
      await api.deleteDepartment(dept.department_id);
      refresh();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Failed to delete department");
    }
  }

  return (
    <div className="page">
      <div className="page-header">
        <h2>Departments</h2>
        <p className="scope-note">
          Master/reference data, not row-level-scoped — anyone with department.view sees the full list.
          What's scoped is who may <em>assign</em> a given department to an employee (see the Employees
          page's edit form).
        </p>
      </div>

      {hasPermission("department.add") && (
        <button className="btn-primary" style={{ marginBottom: "1rem" }} onClick={() => setCreating(true)}>
          Add department
        </button>
      )}

      {error && <div className="form-error" style={{ marginBottom: "1rem" }}>{error}</div>}

      {loading ? (
        <div className="page-loading">Loading…</div>
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Location</th>
              {(hasPermission("department.edit") || hasPermission("department.delete")) && <th></th>}
            </tr>
          </thead>
          <tbody>
            {departments.map((d) => (
              <tr key={d.department_id}>
                <td>{d.department_name}</td>
                <td>{d.location_name}</td>
                {(hasPermission("department.edit") || hasPermission("department.delete")) && (
                  <td className="row-actions">
                    {hasPermission("department.edit") && (
                      <button className="btn-secondary" onClick={() => setEditing(d)}>
                        Edit
                      </button>
                    )}
                    {hasPermission("department.delete") && (
                      <button className="btn-secondary" onClick={() => handleDelete(d)}>
                        Delete
                      </button>
                    )}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {(editing || creating) && (
        <DepartmentFormModal
          department={editing}
          onClose={() => {
            setEditing(null);
            setCreating(false);
          }}
          onSaved={handleSaved}
        />
      )}
    </div>
  );
}
