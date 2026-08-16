import { useEffect, useState } from "react";
import { api } from "../api/client";
import { useAuth } from "../auth/AuthContext";
import { EmployeeEditModal } from "../components/EmployeeEditModal";
import type { Employee } from "../types";

export function Employees() {
  const { user, hasPermission } = useAuth();
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<Employee | null>(null);

  useEffect(() => {
    api
      .employees()
      .then(setEmployees)
      .finally(() => setLoading(false));
  }, []);

  function handleSaved(updated: Employee) {
    setEmployees((rows) => rows.map((e) => (e.employee_id === updated.employee_id ? updated : e)));
    setEditing(null);
  }

  return (
    <div className="page">
      <div className="page-header">
        <h2>Employees</h2>
        <p className="scope-note">
          Showing rows visible under your <strong>{user?.scope_types.join(", ")}</strong> data scope — this list
          comes from a single query joining Employees, Departments, Sections, Locations, and a self-join for
          each manager, with no scope filtering written in the query itself.
        </p>
      </div>

      {loading ? (
        <div className="page-loading">Loading…</div>
      ) : employees.length === 0 ? (
        <div className="empty-state">No employees visible in your data scope.</div>
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Job title</th>
              <th>Department</th>
              <th>Section</th>
              <th>Location</th>
              <th>Manager</th>
              <th>Hire date</th>
              <th>Email</th>
              {hasPermission("employee.edit") && <th></th>}
            </tr>
          </thead>
          <tbody>
            {employees.map((e) => (
              <tr key={e.employee_id}>
                <td>{e.full_name}</td>
                <td>{e.job_title}</td>
                <td>{e.department_name}</td>
                <td>{e.section_name ?? <span className="muted">—</span>}</td>
                <td>{e.location_name}</td>
                <td>{e.manager_name ?? <span className="muted">—</span>}</td>
                <td>{e.hire_date}</td>
                <td>{e.email}</td>
                {hasPermission("employee.edit") && (
                  <td>
                    <button className="btn-secondary" onClick={() => setEditing(e)}>
                      Edit
                    </button>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {editing && (
        <EmployeeEditModal employee={editing} onClose={() => setEditing(null)} onSaved={handleSaved} />
      )}
    </div>
  );
}
