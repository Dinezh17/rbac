import { Navigate, Route, BrowserRouter as Router, Routes } from "react-router-dom";
import { AuthProvider, useAuth } from "./auth/AuthContext";
import { Navbar } from "./components/Navbar";
import { ProtectedRoute } from "./components/ProtectedRoute";
import { Employees } from "./pages/Employees";
import { Leave } from "./pages/Leave";
import { Login } from "./pages/Login";
import { Payroll } from "./pages/Payroll";

function Shell() {
  const { user } = useAuth();
  return (
    <>
      <Navbar />
      <main className="app-main">
        <Routes>
          <Route path="/login" element={user ? <Navigate to="/employees" replace /> : <Login />} />
          <Route
            path="/employees"
            element={
              <ProtectedRoute requirePermission="employee:read">
                <Employees />
              </ProtectedRoute>
            }
          />
          <Route
            path="/payroll"
            element={
              <ProtectedRoute requirePermission="payroll:read">
                <Payroll />
              </ProtectedRoute>
            }
          />
          <Route
            path="/leave"
            element={
              <ProtectedRoute requirePermission="leave:read">
                <Leave />
              </ProtectedRoute>
            }
          />
          <Route path="*" element={<Navigate to={user ? "/employees" : "/login"} replace />} />
        </Routes>
      </main>
    </>
  );
}

function App() {
  return (
    <Router>
      <AuthProvider>
        <Shell />
      </AuthProvider>
    </Router>
  );
}

export default App;
