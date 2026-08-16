import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";

const DEMO_ACCOUNTS = [
  { username: "alice.chen", role: "Executive", scope: "ALL — sees + can assign everything" },
  {
    username: "bob.singh",
    role: "HR Business Partner",
    scope: "SELECTED — dept HR+Finance (visibility), section Core HR+Core Finance only (assignable)",
  },
  { username: "carol.mehta", role: "Engineering Manager", scope: "TEAM — herself + her reporting subtree" },
  { username: "david.kim", role: "Employee", scope: "OWN — herself only" },
  {
    username: "nina.rao",
    role: "Talent & Enterprise Analyst",
    scope: "SELECTED — Section only (Talent Acquisition + Enterprise), no Department at all — spans HR and Sales",
  },
];

export function Login() {
  const { login, error } = useAuth();
  const navigate = useNavigate();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("Passw0rd!");
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    try {
      await login(username, password);
      navigate("/employees");
    } catch {
      // error is surfaced via auth context state
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <h1>Lakshmi Corp HRMS</h1>
        <p className="login-subtitle">RBAC + data-scope demo</p>

        <form onSubmit={handleSubmit} className="login-form">
          <label>
            Username
            <input value={username} onChange={(e) => setUsername(e.target.value)} required autoFocus />
          </label>
          <label>
            Password
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
          </label>
          {error && <div className="form-error">{error}</div>}
          <button type="submit" className="btn-primary" disabled={submitting}>
            {submitting ? "Signing in…" : "Sign in"}
          </button>
        </form>

        <div className="demo-accounts">
          <div className="demo-accounts-title">Demo accounts (password: Passw0rd!)</div>
          <table>
            <thead>
              <tr>
                <th>Username</th>
                <th>Role</th>
                <th>Data scope</th>
              </tr>
            </thead>
            <tbody>
              {DEMO_ACCOUNTS.map((acct) => (
                <tr
                  key={acct.username}
                  onClick={() => setUsername(acct.username)}
                  className="demo-account-row"
                >
                  <td>{acct.username}</td>
                  <td>{acct.role}</td>
                  <td>{acct.scope}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
