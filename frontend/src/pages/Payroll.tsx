import { useEffect, useState } from "react";
import { api } from "../api/client";
import type { Payroll as PayrollRecord } from "../types";

function formatCurrency(value: string): string {
  return new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 }).format(
    Number(value)
  );
}

export function Payroll() {
  const [rows, setRows] = useState<PayrollRecord[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api
      .payroll()
      .then(setRows)
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="page">
      <div className="page-header">
        <h2>Payroll</h2>
        <p className="scope-note">
          Same data-scope policy, a completely different table — Payroll has its own EmployeeId owner
          column and gets the identical enforcement with zero extra scope code.
        </p>
      </div>

      {loading ? (
        <div className="page-loading">Loading…</div>
      ) : rows.length === 0 ? (
        <div className="empty-state">No payroll records visible in your data scope.</div>
      ) : (
        <table className="data-table">
          <thead>
            <tr>
              <th>Employee</th>
              <th>Department</th>
              <th>Pay period</th>
              <th>Base salary</th>
              <th>Bonus</th>
              <th>Deductions</th>
              <th>Net pay</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.payroll_id}>
                <td>{r.employee_name}</td>
                <td>{r.department_name}</td>
                <td>{r.pay_period}</td>
                <td>{formatCurrency(r.base_salary)}</td>
                <td>{formatCurrency(r.bonus)}</td>
                <td>{formatCurrency(r.deductions)}</td>
                <td className="net-pay">{formatCurrency(r.net_pay)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
