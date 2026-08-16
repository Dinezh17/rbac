import { useEffect, useState } from "react";
import { api, ApiError } from "../api/client";
import type { Department, Location } from "../types";

interface Props {
  department: Department | null; // null = creating a new one
  onClose: () => void;
  onSaved: (department: Department) => void;
}

export function DepartmentFormModal({ department, onClose, onSaved }: Props) {
  const [name, setName] = useState(department?.department_name ?? "");
  const [locationId, setLocationId] = useState<number | "">(department?.location_id ?? "");
  const [locations, setLocations] = useState<Location[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.locations().then((rows) => {
      setLocations(rows);
      if (locationId === "" && rows.length > 0) setLocationId(rows[0].location_id);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (locationId === "") return;
    setSaving(true);
    setError(null);
    try {
      const saved = department
        ? await api.updateDepartment(department.department_id, { department_name: name, location_id: locationId })
        : await api.createDepartment({ department_name: name, location_id: locationId });
      onSaved(saved);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Failed to save department");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-card" onClick={(e) => e.stopPropagation()}>
        <h3>{department ? `Edit ${department.department_name}` : "New department"}</h3>
        <form onSubmit={handleSubmit} className="modal-form">
          <label>
            Department name
            <input value={name} onChange={(e) => setName(e.target.value)} required autoFocus />
          </label>
          <label>
            Location
            <select value={locationId} onChange={(e) => setLocationId(Number(e.target.value))}>
              {locations.map((l) => (
                <option key={l.location_id} value={l.location_id}>
                  {l.location_name}
                </option>
              ))}
            </select>
          </label>
          {error && <div className="form-error">{error}</div>}
          <div className="modal-actions">
            <button type="button" className="btn-secondary" onClick={onClose}>
              Cancel
            </button>
            <button type="submit" className="btn-primary" disabled={saving}>
              {saving ? "Saving…" : "Save"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
