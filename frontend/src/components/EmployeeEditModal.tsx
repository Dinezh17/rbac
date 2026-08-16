import { useEffect, useState } from "react";
import { api, ApiError } from "../api/client";
import type { AssignableOption, Employee, EmployeeUpdate } from "../types";

interface Props {
  employee: Employee;
  onClose: () => void;
  onSaved: (updated: Employee) => void;
}

// The core answer to "an editor can't see the LOV item the record's
// creator picked": a scoped field renders in one of two modes.
//   - The current value IS in the caller's assignable set -> a normal,
//     editable dropdown restricted to that set.
//   - The current value is NOT in the caller's assignable set -> a
//     disabled, read-only display of the current value, with a note
//     explaining why. That field is then never included in the PATCH
//     payload at all, so leaving it alone can never be mistaken for
//     "clear this field" - see EmployeeUpdate/exclude_unset handling in
//     backend/app/routers/employees.py::update_employee.
export function EmployeeEditModal({ employee, onClose, onSaved }: Props) {
  const [fullName, setFullName] = useState(employee.full_name);
  const [jobTitle, setJobTitle] = useState(employee.job_title);
  const [departmentId, setDepartmentId] = useState(employee.department_id);
  const [sectionId, setSectionId] = useState<number | null>(employee.section_id);

  const [assignableDepartments, setAssignableDepartments] = useState<AssignableOption[] | null>(null);
  const [assignableSections, setAssignableSections] = useState<AssignableOption[] | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([api.assignableDepartments(), api.assignableSections()]).then(
      ([departments, sections]) => {
        setAssignableDepartments(departments);
        setAssignableSections(sections);
      }
    );
  }, []);

  const loadingScope = assignableDepartments === null || assignableSections === null;
  const departmentLocked =
    !loadingScope && !assignableDepartments!.some((d) => d.id === employee.department_id);
  const sectionLocked =
    !loadingScope &&
    employee.section_id !== null &&
    !assignableSections!.some((s) => s.id === employee.section_id);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const changes: EmployeeUpdate = {};
    if (fullName !== employee.full_name) changes.full_name = fullName;
    if (jobTitle !== employee.job_title) changes.job_title = jobTitle;
    // Locked fields are structurally excluded - there's no code path that
    // could add them here even if the values above happened to differ.
    if (!departmentLocked && departmentId !== employee.department_id) changes.department_id = departmentId;
    if (!sectionLocked && sectionId !== employee.section_id) changes.section_id = sectionId;

    if (Object.keys(changes).length === 0) {
      onClose();
      return;
    }

    setSaving(true);
    try {
      const updated = await api.updateEmployee(employee.employee_id, changes);
      onSaved(updated);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Failed to save changes");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-card" onClick={(e) => e.stopPropagation()}>
        <h3>Edit {employee.full_name}</h3>

        <form onSubmit={handleSubmit} className="modal-form">
          <label>
            Full name
            <input value={fullName} onChange={(e) => setFullName(e.target.value)} required />
          </label>
          <label>
            Job title
            <input value={jobTitle} onChange={(e) => setJobTitle(e.target.value)} required />
          </label>

          <label>
            Department
            {loadingScope ? (
              <input value="Loading…" disabled />
            ) : departmentLocked ? (
              <>
                <input value={employee.department_name} disabled />
                <span className="field-lock-note">
                  Outside your assignable scope - you can edit other fields, but not reassign this one.
                </span>
              </>
            ) : (
              <select value={departmentId} onChange={(e) => setDepartmentId(Number(e.target.value))}>
                {assignableDepartments!.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.name}
                  </option>
                ))}
              </select>
            )}
          </label>

          <label>
            Section
            {loadingScope ? (
              <input value="Loading…" disabled />
            ) : sectionLocked ? (
              <>
                <input value={employee.section_name ?? ""} disabled />
                <span className="field-lock-note">
                  Outside your assignable scope - you can edit other fields, but not reassign this one.
                </span>
              </>
            ) : (
              <select
                value={sectionId ?? ""}
                onChange={(e) => setSectionId(e.target.value ? Number(e.target.value) : null)}
              >
                <option value="">— none —</option>
                {assignableSections!.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
            )}
          </label>

          {error && <div className="form-error">{error}</div>}

          <div className="modal-actions">
            <button type="button" className="btn-secondary" onClick={onClose}>
              Cancel
            </button>
            <button type="submit" className="btn-primary" disabled={saving || loadingScope}>
              {saving ? "Saving…" : "Save changes"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
