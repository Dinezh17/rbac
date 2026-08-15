import { useEffect, useState } from "react";
import { api, ApiError } from "../api/client";
import { useAuth } from "../auth/AuthContext";
import type { LeaveRequest } from "../types";

export function Leave() {
  const { hasPermission } = useAuth();
  const [rows, setRows] = useState<LeaveRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [formError, setFormError] = useState<string | null>(null);
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [leaveType, setLeaveType] = useState("ANNUAL");
  const [submitting, setSubmitting] = useState(false);

  function refresh() {
    setLoading(true);
    api
      .leaveRequests()
      .then(setRows)
      .finally(() => setLoading(false));
  }

  useEffect(refresh, []);

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    setFormError(null);
    setSubmitting(true);
    try {
      await api.createLeaveRequest({ start_date: startDate, end_date: endDate, leave_type: leaveType });
      setStartDate("");
      setEndDate("");
      refresh();
    } catch (err) {
      setFormError(err instanceof ApiError ? err.message : "Failed to submit request");
    } finally {
      setSubmitting(false);
    }
  }

  async function handleApprove(id: number) {
    try {
      await api.approveLeaveRequest(id);
      refresh();
    } catch (err) {
      alert(err instanceof ApiError ? err.message : "Failed to approve request");
    }
  }

  return (
    <div className="page">
      <div className="page-header">
        <h2>Leave requests</h2>
        <p className="scope-note">
          Approvals are validated twice: the "leave.approve" permission (RBAC) gates the button, and the
          database's row-level security decides which requests you can even reach — approving a request
          outside your data scope fails as if it doesn't exist.
        </p>
      </div>

      {hasPermission("leave.add") && (
        <form onSubmit={handleCreate} className="leave-form">
          <label>
            Start date
            <input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} required />
          </label>
          <label>
            End date
            <input type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} required />
          </label>
          <label>
            Type
            <select value={leaveType} onChange={(e) => setLeaveType(e.target.value)}>
              <option value="ANNUAL">Annual</option>
              <option value="SICK">Sick</option>
              <option value="UNPAID">Unpaid</option>
            </select>
          </label>
          <button type="submit" className="btn-primary" disabled={submitting}>
            {submitting ? "Submitting…" : "Request leave"}
          </button>
          {formError && <div className="form-error">{formError}</div>}
        </form>
      )}

      {loading ? (
        <div className="page-loading">Loading…</div>
      ) : rows.length === 0 ? (
        <div className="empty-state">No leave requests visible in your data scope.</div>
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Employee</th>
              <th>Type</th>
              <th>Start</th>
              <th>End</th>
              <th>Status</th>
              {hasPermission("leave.approve") && <th></th>}
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.leave_request_id}>
                <td>{r.employee_name}</td>
                <td>{r.leave_type}</td>
                <td>{r.start_date}</td>
                <td>{r.end_date}</td>
                <td>
                  <span className={`status-badge status-${r.status.toLowerCase()}`}>{r.status}</span>
                </td>
                {hasPermission("leave.approve") && (
                  <td>
                    {r.status === "PENDING" && (
                      <button className="btn-secondary" onClick={() => handleApprove(r.leave_request_id)}>
                        Approve
                      </button>
                    )}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
