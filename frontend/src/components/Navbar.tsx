import { NavLink, useNavigate } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";

export function Navbar() {
  const { user, logout, hasPermission } = useAuth();
  const navigate = useNavigate();

  if (!user) return null;

  function handleLogout() {
    logout();
    navigate("/login");
  }

  return (
    <header className="navbar">
      <div className="navbar-brand">Lakshmi Corp HRMS</div>
      <nav className="navbar-links">
        {hasPermission("employee:read") && (
          <NavLink to="/employees" className={({ isActive }) => (isActive ? "active" : "")}>
            Employees
          </NavLink>
        )}
        {hasPermission("payroll:read") && (
          <NavLink to="/payroll" className={({ isActive }) => (isActive ? "active" : "")}>
            Payroll
          </NavLink>
        )}
        {hasPermission("leave:read") && (
          <NavLink to="/leave" className={({ isActive }) => (isActive ? "active" : "")}>
            Leave
          </NavLink>
        )}
      </nav>
      <div className="navbar-user">
        <div className="navbar-user-info">
          <span className="navbar-username">{user.username}</span>
          <span className="navbar-role">
            {user.roles.join(", ")} · {user.scope_types.join(", ")} scope
          </span>
        </div>
        <button className="btn-secondary" onClick={handleLogout}>
          Log out
        </button>
      </div>
    </header>
  );
}
