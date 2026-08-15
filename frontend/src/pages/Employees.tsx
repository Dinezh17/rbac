import { useEffect, useState } from "react";
import { api } from "../api/client";
import { useAuth } from "../auth/AuthContext";
import type { Employee } from "../types";

export function Employees() {
  const { user } = useAuth();
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api
      .employees()
      .then(setEmployees)
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="page">
      <div className="page-header">
        <h2>Employees</h2>
        <p className="scope-note">
          Showing rows visible under your <strong>{user?.scope_types.join(", ")}</strong> data scope — this list
          comes from a single query joining Employees, Departments, Locations, and a self-join for each
          manager, with no scope filtering written in the query itself.
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
              <th>Location</th>
              <th>Manager</th>
              <th>Hire date</th>
              <th>Email</th>
            </tr>
          </thead>
          <tbody>
            {employees.map((e) => (
              <tr key={e.employee_id}>
                <td>{e.full_name}</td>
                <td>{e.job_title}</td>
                <td>{e.department_name}</td>
                <td>{e.location_name}</td>
                <td>{e.manager_name ?? <span className="muted">—</span>}</td>
                <td>{e.hire_date}</td>
                <td>{e.email}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
